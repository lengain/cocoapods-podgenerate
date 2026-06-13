# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches Pod::Project to cache pod_group lookups.
# Original implementation does O(n) linear scan for every pod_group call:
#   pod_groups.find { |group| group.name == pod_name }
#
# With 200+ pods and pod_group called 3-5 times per pod, this is 600-1000
# linear scans of a 200-element array = ~120k-200k iterations.
#
# Fix: cache groups in a Hash for O(1) lookup. Invalidate on add_pod_group.
#
# Reference: CocoaPods source — lib/cocoapods/project.rb

module Pod
  module PodGenerate
    module Patches
      module ProjectPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying ProjectPatch (pod_group hash cache)'
          Pod::Project.prepend(CachedPodGroup)
        end

        module CachedPodGroup
          # Build a hash cache of pod_name => PBXGroup
          # Called once when first needed, then kept in sync.
          def pod_group(pod_name)
            @pod_group_cache ||= build_pod_group_cache
            @pod_group_cache[pod_name]
          end

          # Override add_pod_group to invalidate the cache
          def add_pod_group(pod_name, path, development = false, absolute = false)
            group = super
            # Invalidate cache so the next call to pod_group rebuilds it
            @pod_group_cache = nil if defined?(@pod_group_cache)
            group
          end

          private

          def build_pod_group_cache
            cache = {}
            pod_groups.each do |group|
              cache[group.name] = group
            end
            cache
          end
        end
      end
    end
  end
end
