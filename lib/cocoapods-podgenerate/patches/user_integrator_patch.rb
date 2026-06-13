# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches UserProjectIntegrator to parallelize and optimize the
# "Integrating client project" step (step 4 of pod install).
#
# v0.1.1:
# 1. Parallelizes integrate_user_targets using threads
# 2. Parallelizes save_projects using threads
#
# v0.1.2:
# 3. Parallelizes warn_about_xcconfig_overrides using threads
#
# Reference: CocoaPods source
#   - lib/cocoapods/installer/user_project_integrator.rb

require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module UserIntegratorPatch
        IGNORED_KEYS = %w(CODE_SIGN_IDENTITY).freeze
        INHERITED_FLAGS = %w($(inherited) ${inherited}).freeze

        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying UserIntegratorPatch v2 (parallel client integration + xcconfig warnings)'
          Pod::Installer::UserProjectIntegrator.prepend(ParallelIntegration)
        end

        module ParallelIntegration
          # ── Optimization 1: Parallel integrate_user_targets ──
          def integrate_user_targets
            target_integrators = targets_to_integrate.sort_by(&:name).map do |target|
              Pod::Installer::UserProjectIntegrator::TargetIntegrator.new(target, :use_input_output_paths => use_input_output_paths?)
            end

            if target_integrators.size <= 1
              target_integrators.each(&:integrate!)
              return
            end

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

          # ── Optimization 2: Parallel save_projects ──
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

          # ── Optimization 3: Parallel warn_about_xcconfig_overrides ──
          # Overrides the original method by prepend — called automatically from integrate!
          def warn_about_xcconfig_overrides
            targets = targets_to_integrate
            return if targets.empty?

            if targets.size <= 1
              warn_single_target(targets.first)
              return
            end

            pool_size = compute_pool_size
            Pod::UI.message "- Checking xcconfig overrides for #{targets.size} targets (pool: #{pool_size})"
            pool = Concurrent::FixedThreadPool.new(pool_size)
            targets.each do |aggregate_target|
              pool.post do
                warn_single_target(aggregate_target)
              rescue StandardError => e
                Pod::UI.warn "[cocoapods-podgenerate] Xcconfig warning error: #{e.message}"
              end
            end
            pool.shutdown
            pool.wait_for_termination
          rescue NameError
            targets.each { |t| warn_single_target(t) }
          end

          private

          # Per-target xcconfig override check. Runs inside a thread pool slot.
          # NOTE: `print_override_warning` is a private method on the original
          # UserProjectIntegrator class. Ruby allows implicit-receiver calls to
          # private methods from prepended modules (no explicit `self.` prefix).
          def warn_single_target(aggregate_target)
            aggregate_target.user_targets.each do |user_target|
              user_target.build_configurations.each do |config|
                xcconfig = aggregate_target.xcconfigs[config.name]
                next unless xcconfig

                (xcconfig.to_hash.keys - UserIntegratorPatch::IGNORED_KEYS).each do |key|
                  target_values = config.build_settings[key]
                  if target_values &&
                      !UserIntegratorPatch::INHERITED_FLAGS.any? { |flag| target_values.include?(flag) }
                    print_override_warning(aggregate_target, user_target, config, key)
                  end
                end
              end
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
