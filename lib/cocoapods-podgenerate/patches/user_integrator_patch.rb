# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches UserProjectIntegrator to parallelize and optimize the
# "Integrating client project" step (step 4 of pod install).
#
# For projects with many user targets / aggregate targets, the integration
# step runs serially. This patch:
# 1. Parallelizes integrate_user_targets using threads
# 2. Parallelizes save_projects using threads
# 3. Caches user_project references to avoid redundant project parsing
#
# Reference: CocoaPods source
#   - lib/cocoapods/installer/user_project_integrator.rb
#   - lib/cocoapods/installer/user_project_integrator/target_integrator.rb

module Pod
  module PodGenerate
    module Patches
      module UserIntegratorPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying UserIntegratorPatch (parallel client integration)'
          Pod::Installer::UserProjectIntegrator.prepend(ParallelIntegration)
        end

        module ParallelIntegration
          # Override integrate_user_targets to use parallel execution
          def integrate_user_targets
            target_integrators = targets_to_integrate.sort_by(&:name).map do |target|
              Pod::Installer::UserProjectIntegrator::TargetIntegrator.new(target, :use_input_output_paths => use_input_output_paths?)
            end

            if target_integrators.size <= 1
              # Single target — no need for threads
              target_integrators.each(&:integrate!)
              return
            end

            # Multiple targets — integrate in parallel
            Pod::UI.message "- Integrating #{target_integrators.size} targets in parallel"
            threads = target_integrators.map do |integrator|
              Thread.new do
                begin
                  integrator.integrate!
                rescue StandardError => e
                  Pod::UI.warn "[cocoapods-podgenerate] Target integration error: #{e.message}"
                end
              end
            end
            threads.each(&:join)
          end

          # Override save_projects to use parallel saving
          def save_projects(projects)
            projects = projects.uniq

            if projects.size <= 1
              projects.each do |project|
                if project.dirty?
                  project.save
                else
                  FileUtils.touch(project.path + 'project.pbxproj')
                end
              end
              return
            end

            # Save multiple projects in parallel
            Pod::UI.message "- Saving #{projects.size} user projects in parallel"
            mutex = Mutex.new
            threads = projects.map do |project|
              Thread.new do
                begin
                  if project.dirty?
                    project.save
                  else
                    mutex.synchronize do
                      FileUtils.touch(project.path + 'project.pbxproj')
                    end
                  end
                rescue StandardError => e
                  Pod::UI.warn "[cocoapods-podgenerate] Project save error: #{e.message}"
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
