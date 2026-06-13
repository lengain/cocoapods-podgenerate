# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches PodsProjectGenerator to optimize "Generating Pods project".
#
# Optimizations:
#  1. Parallelize PodTargetIntegrator integration (multiple pods at once)
#  2. Delegate install_pod_targets to original (safe, no threading issues)
#
# Reference: CocoaPods — lib/cocoapods/installer/xcode/pods_project_generator.rb

module Pod
  module PodGenerate
    module Patches
      module InstallerPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying InstallerPatch (optimized integration)'
          Pod::Installer::Xcode::PodsProjectGenerator.prepend(ParallelInstall)
        end

        module ParallelInstall
          def install_pod_targets(project, pod_targets)
            super
          end

          # Override integrate_targets to run in parallel
          def integrate_targets(pod_target_installation_results)
            pods_to_integrate = pod_target_installation_results.values.select do |result|
              target = result.target
              !result.test_native_targets.empty? ||
                !result.app_native_targets.empty? ||
                target.contains_script_phases? ||
                target.framework_paths.values.flatten.any? { |p| !p.dsym_path.nil? } ||
                target.xcframeworks.values.any?(&:any?)
            end
            return if pods_to_integrate.empty?

            use_io_paths = !installation_options.disable_input_output_paths
            threads = pods_to_integrate.map do |result|
              Thread.new do
                begin
                  Pod::Installer::Xcode::PodsProjectGenerator::PodTargetIntegrator.new(
                    result, :use_input_output_paths => use_io_paths
                  ).integrate!
                rescue StandardError => e
                  Pod::UI.warn "[cocoapods-podgenerate] Integrate error: #{e.message}"
                end
              end
            end
            threads.each(&:join)
          end
        end
      end
    end
  end
end
