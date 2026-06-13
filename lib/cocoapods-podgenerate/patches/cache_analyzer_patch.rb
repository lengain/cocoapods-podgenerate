# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches ProjectCacheAnalyzer to parallelize cache key computation.
#
# v0.1.2 Optimization:
#  1. Parallel MD5 cache key computation across all pod targets
#
# TargetCacheKey.from_pod_target computes MD5 checksums of build settings
# and collects resource dependencies per target. Each computation is fully
# independent and can run in parallel.
#
# Reference: CocoaPods — lib/cocoapods/installer/project_cache/project_cache_analyzer.rb

require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module CacheAnalyzerPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying CacheAnalyzerPatch (parallel cache key computation)'
          Pod::Installer::ProjectCache::ProjectCacheAnalyzer.prepend(ParallelCacheKeyComputation)
        end

        module ParallelCacheKeyComputation
          # Override create_cache_key_mappings to parallelize MD5 computation
          # The original iterates target_by_label sequentially, computing cache keys.
          # Since each target is independent, we use a thread pool.
          def create_cache_key_mappings(target_by_label)
            UI.message '- Creating cache key mappings (parallel)' do
              pool_size = compute_pool_size
              pool = Concurrent::FixedThreadPool.new(pool_size)
              mutex = Mutex.new
              results = {}

              target_by_label.each do |label, target|
                pool.post do
                  key = compute_cache_key(target, target_by_label)
                  mutex.synchronize { results[label] = key }
                rescue StandardError => e
                  # Bug fix v0.1.3: compute fallback key synchronously to avoid nil
                  # entries that would crash ProjectCacheAnalyzer#analyze downstream
                  Pod::UI.warn "[cocoapods-podgenerate] Cache key computation error, retrying sync: #{e.message}"
                  fallback_key = compute_cache_key(target, target_by_label)
                  mutex.synchronize { results[label] = fallback_key }
                end
              end

              pool.shutdown
              pool.wait_for_termination
              results
            end
          end

          private

          def compute_cache_key(target, target_by_label)
            case target
            when PodTarget
              local = sandbox.local?(target.pod_name)
              checkout_options = sandbox.checkout_sources[target.pod_name]
              TargetCacheKey.from_pod_target(sandbox, target_by_label, target,
                                             :is_local_pod => local,
                                             :checkout_options => checkout_options)
            when AggregateTarget
              TargetCacheKey.from_aggregate_target(sandbox, target_by_label, target)
            else
              raise "[BUG] Unknown target type #{target}"
            end
          end

          def compute_pool_size
            [[Etc.nprocessors - 1, 2].max, 16].min
          rescue NameError
            4
          end
        end
      end
    end
  end
end
