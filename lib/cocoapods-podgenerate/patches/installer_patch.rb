# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches Pod::Installer and PodsProjectGenerator for step 3/4 optimizations.
#
# v0.1.1 Optimizations:
#  1. Force-enable incremental_installation + generate_multiple_pod_projects
#  2. Skip project generation entirely when nothing changed
#  3. Parallelize PodTargetIntegrator integration
#
# Reference: CocoaPods — lib/cocoapods/installer.rb

module Pod
  module PodGenerate
    module Patches
      module InstallerPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying InstallerPatch v2'
          Pod::Installer.prepend(ForceIncrementalInstall)
          Pod::Installer::Xcode::PodsProjectGenerator.prepend(ParallelInstall)
        end

        # ── Optimization 1: Force-enable incremental_installation ──
        module ForceIncrementalInstall
          def install!
            installation_options.incremental_installation = true
            installation_options.generate_multiple_pod_projects = true
            super
          end

          # ── Optimization 2: Skip project generation when nothing changed ──
          def generate_pods_project
            stage_sandbox(sandbox, pod_targets)

            cache_analysis_result = analyze_project_cache
            ptg = cache_analysis_result.pod_targets_to_generate
            atg = cache_analysis_result.aggregate_targets_to_generate

            if ptg.empty? && (atg.nil? || atg.empty?)
              Pod::UI.puts "[cocoapods-podgenerate] No changes — skipping project generation"
              @generated_aggregate_targets = aggregate_targets
              @generated_pod_targets = []
              Pod::Installer::SandboxDirCleaner.new(sandbox, pod_targets, aggregate_targets).clean!
              update_project_cache(cache_analysis_result,
                Pod::Installer::Xcode::PodsProjectGenerator::InstallationResults.new({}, {}))
              return
            end

            # Normal path
            ptg.each do |pod_target|
              pod_target.build_headers.implode_path!(pod_target.headers_sandbox)
              sandbox.public_headers.implode_path!(pod_target.headers_sandbox)
            end

            create_and_save_projects(ptg, atg,
              cache_analysis_result.build_configurations, cache_analysis_result.project_object_version)
            Pod::Installer::SandboxDirCleaner.new(sandbox, pod_targets, aggregate_targets).clean!
            update_project_cache(cache_analysis_result, target_installation_results)
          end
        end

        # ── Optimization 3: Parallelize PodTargetIntegrator ──
        module ParallelInstall
          def install_pod_targets(project, pod_targets)
            super
          end

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
