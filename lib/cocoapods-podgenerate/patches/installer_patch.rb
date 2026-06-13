# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches Pod::Installer and PodsProjectGenerator for step 3/4 optimizations.
#
# v0.1.1 Optimizations:
#  1. Force-enable incremental_installation + generate_multiple_pod_projects
#  2. Skip project generation entirely when nothing changed
#  3. Parallelize PodTargetIntegrator integration
#
# v0.1.2 Optimization:
#  4. Parallelize configure_schemes across projects
#
# Reference: CocoaPods — lib/cocoapods/installer.rb
#            lib/cocoapods/installer/xcode/pods_project_generator.rb

require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module InstallerPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying InstallerPatch v3'
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

          # ── Optimization 3+4: create_and_save_projects with parallel configure_schemes ──
          def create_and_save_projects(pod_targets_to_generate, aggregate_targets_to_generate,
                                       build_configurations, project_object_version)
            UI.section 'Generating Pods project' do
              generator = create_generator(pod_targets_to_generate, aggregate_targets_to_generate,
                                           build_configurations, project_object_version,
                                           installation_options.generate_multiple_pod_projects)

              pod_project_generation_result = generator.generate!
              @target_installation_results = pod_project_generation_result.target_installation_results
              @pods_project = pod_project_generation_result.project
              @pod_target_subprojects = pod_project_generation_result.projects_by_pod_targets.keys
              @generated_projects = ([pods_project] + pod_target_subprojects || []).compact
              @generated_pod_targets = pod_targets_to_generate
              @generated_aggregate_targets = aggregate_targets_to_generate || []
              projects_by_pod_targets = pod_project_generation_result.projects_by_pod_targets

              predictabilize_uuids(generated_projects) if installation_options.deterministic_uuids?
              stabilize_target_uuids(generated_projects)

              projects_writer = Pod::Installer::Xcode::PodsProjectWriter.new(sandbox, generated_projects,
                                                             target_installation_results.pod_target_installation_results,
                                                             installation_options)
              projects_writer.write! do
                run_podfile_post_install_hooks
              end

              # Parallel configure_schemes (each project is independent)
              pods_project_pod_targets = pod_targets_to_generate - projects_by_pod_targets.values.flatten
              all_projects_by_pod_targets = {}
              if pods_project
                all_projects_by_pod_targets[pods_project] = pods_project_pod_targets
              end
              all_projects_by_pod_targets.merge!(projects_by_pod_targets) if projects_by_pod_targets

              if all_projects_by_pod_targets.size > 1
                parallel_configure_schemes(all_projects_by_pod_targets, generator, pod_project_generation_result)
              else
                all_projects_by_pod_targets.each do |project, pts|
                  generator.configure_schemes(project, pts, pod_project_generation_result)
                end
              end
            end
          end

          private

          def parallel_configure_schemes(projects_by_pod_targets, generator, generation_result)
            pool_size = [[Etc.nprocessors - 1, 2].max, 16].min
            Pod::UI.message "- Configuring schemes across #{projects_by_pod_targets.size} projects (pool: #{pool_size})"

            pool = Concurrent::FixedThreadPool.new(pool_size)
            projects_by_pod_targets.each do |project, pts|
              pool.post do
                generator.configure_schemes(project, pts, generation_result)
              rescue StandardError => e
                Pod::UI.warn "[cocoapods-podgenerate] Scheme configuration error: #{e.message}"
              end
            end
            pool.shutdown
            pool.wait_for_termination
          rescue NameError
            # Fallback: sequential
            projects_by_pod_targets.each do |project, pts|
              generator.configure_schemes(project, pts, generation_result)
            end
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
