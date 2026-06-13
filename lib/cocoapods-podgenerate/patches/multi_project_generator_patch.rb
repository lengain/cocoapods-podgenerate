# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches MultiPodsProjectGenerator to parallelize pod target installation.
#
# v0.1.2 Optimization:
#  1. Parallel install_all_pod_targets — each pod target's install is independent I/O
#
# Architecture:
#  Instead of overriding create_pods_project (which has Ruby constant resolution issues
#  in prepended modules for PodsProjectGenerator's inner classes), we keep the original
#  project creation + file references sequential, and only parallelize the pod target
#  installation step which is the heaviest I/O operation.
#
# Reference: CocoaPods — lib/cocoapods/installer/xcode/multi_pods_project_generator.rb
#            lib/cocoapods/installer/xcode/pods_project_generator.rb

require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module MultiProjectGeneratorPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying MultiProjectGeneratorPatch (parallel pod target install)'
          Pod::Installer::Xcode::MultiPodsProjectGenerator.prepend(ParallelMultiProjectGenerator)
        end

        module ParallelMultiProjectGenerator
          # ── Optimization: Parallel install_all_pod_targets ──
          # Each project has independent pod targets (different xcodeproj directories),
          # so PodTargetInstaller operations can run concurrently without locking.
          def install_all_pod_targets(projects_by_pod_targets)
            UI.message '- Installing Pod Targets (parallel)' do
              pool_size = compute_pool_size
              mutex = Mutex.new
              all_results = {}

              pool = Concurrent::FixedThreadPool.new(pool_size)
              projects_by_pod_targets.each do |project, pts|
                pool.post do
                  target_results = install_pod_targets(project, pts)
                  mutex.synchronize { all_results.merge!(target_results) }
                rescue StandardError => e
                  mutex.synchronize do
                    Pod::UI.warn "[cocoapods-podgenerate] Pod target install: #{e.message}"
                  end
                end
              end

              pool.shutdown
              pool.wait_for_termination
              all_results
            end
          end

          private

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
