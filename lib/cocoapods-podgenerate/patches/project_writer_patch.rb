# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches PodsProjectWriter to support incremental + parallel project saves.
#
# v0.1.1 Optimizations:
#  1. SHA256 digest — skip sort+save for unchanged projects
#  2. Parallel save — multiple xcodeproj files saved in threads
#
# v0.1.2 Optimizations:
#  3. Parallel cleanup_projects — empty group removal across projects
#  4. Parallel recreate_user_schemes — scheme file creation across projects
#
# Reference: CocoaPods — lib/cocoapods/installer/xcode/pods_project_generator/pods_project_writer.rb

require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module ProjectWriterPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying ProjectWriterPatch v3 (incremental + parallel save + parallel write steps)'
          Pod::Installer::Xcode::PodsProjectWriter.prepend(IncrementalAndParallelSave)
        end

        module IncrementalAndParallelSave
          def initialize(sandbox, projects, pod_target_installation_results, installation_options)
            super
            @project_digests = {}
            @projects = projects
            @sort_needed = {}
            compute_initial_digests
          end

          # ── Optimizations 3+4+2: Parallel write! with parallel cleanup + schemes + save ──
          def write!
            # Parallel cleanup (each project is independent)
            parallel_cleanup_projects(@projects)

            # Parallel recreate_user_schemes (each project is independent)
            parallel_recreate_user_schemes(@projects)

            yield if block_given?

            save_projects(@projects)
          end

          # ── Optimization 1: SHA256 skip + parallel save ──
          def save_projects(projects)
            # Filter: skip projects whose pbxproj is unchanged
            to_save = projects.select do |project|
              if project_unchanged?(project)
                Pod::UI.message "- Skipping unchanged project #{UI.path project.path}"
                false
              else
                true
              end
            end
            return if to_save.empty?

            # Sort each project
            to_save.each { |p| p.sort(:groups_position => :below) if needs_sort?(p) }

            # Parallel save (safe: each xcodeproj is an independent directory)
            if to_save.size > 1
              Pod::UI.message "- Saving #{to_save.size} projects in parallel"
              threads = to_save.map do |project|
                Thread.new do
                  begin
                    Pod::UI.message "- Writing Xcode project file to #{UI.path project.path}"
                    project.save
                    update_digest(project)
                  rescue StandardError => e
                    Pod::UI.warn "[cocoapods-podgenerate] Parallel save error: #{e.message}"
                  end
                end
              end
              threads.each(&:join)
            else
              Pod::UI.message "- Writing Xcode project file to #{UI.path to_save.first.path}" do
                to_save.first.save
                update_digest(to_save.first)
              end
            end
          end

          private

          # ── Optimization 3: Parallel cleanup_projects ──

          def parallel_cleanup_projects(projects)
            pool_size = compute_pool_size
            Pod::UI.message "- Cleaning up #{projects.size} projects (pool: #{pool_size})"

            pool = begin
              Concurrent::FixedThreadPool.new(pool_size)
            rescue NameError
              nil
            end

            if pool
              projects.each do |project|
                pool.post do
                  cleanup_single_project(project)
                rescue StandardError => e
                  Pod::UI.warn "[cocoapods-podgenerate] Cleanup error: #{e.message}"
                end
              end
              pool.shutdown
              pool.wait_for_termination
            else
              # Fallback: sequential (Concurrent not available)
              projects.each { |p| cleanup_single_project(p) }
            end
          end

          def cleanup_single_project(project)
            [project.pods, project.support_files_group,
             project.development_pods, project.dependencies_group].each do |group|
              group.remove_from_project if group.respond_to?(:empty?) && group.empty?
            end
          end

          # ── Optimization 4: Parallel recreate_user_schemes ──

          def parallel_recreate_user_schemes(projects)
            library_product_types = [:framework, :dynamic_library, :static_library]

            # Pre-build results_by_native_target once (shared read-only cache)
            results_by_native_target = build_native_target_cache

            pool_size = compute_pool_size
            Pod::UI.message "- Recreating user schemes for #{projects.size} projects (pool: #{pool_size})"

            pool = begin
              Concurrent::FixedThreadPool.new(pool_size)
            rescue NameError
              nil
            end

            if pool
              projects.each do |project|
                pool.post do
                  recreate_schemes_for_project(project, library_product_types, results_by_native_target)
                rescue StandardError => e
                  Pod::UI.warn "[cocoapods-podgenerate] Scheme recreation error: #{e.message}"
                end
              end
              pool.shutdown
              pool.wait_for_termination
            else
              # Fallback: sequential (Concurrent not available)
              projects.each do |project|
                recreate_schemes_for_project(project, library_product_types, results_by_native_target)
              end
            end
          end

          def recreate_schemes_for_project(project, library_product_types, results_by_native_target)
            project.recreate_user_schemes(false) do |scheme, target|
              next unless target.respond_to?(:symbol_type)
              next unless library_product_types.include?(target.symbol_type)
              installation_result = results_by_native_target[target]
              next unless installation_result
              installation_result.test_native_targets.each do |test_native_target|
                scheme.add_test_target(test_native_target)
              end
            end
          end

          def build_native_target_cache
            cache = {}
            @pod_target_installation_results.each do |_, result|
              cache[result.native_target] = result if result.respond_to?(:native_target)
            end
            cache
          end

          # ── Digest helpers (from v0.1.1) ──

          def compute_initial_digests
            @projects.each do |project|
              update_digest(project)
            end
            @projects.each { |p| @sort_needed[p.object_id] = true }
          end

          def project_unchanged?(project)
            pbx_path = pbxproj_path(project)
            return false unless pbx_path && File.exist?(pbx_path)

            old_digest = @project_digests[project.object_id]
            return false unless old_digest

            current_digest = digest_file(pbx_path)
            current_digest == old_digest
          end

          def needs_sort?(project)
            @sort_needed[project.object_id] != false
          end

          def update_digest(project)
            pbx_path = pbxproj_path(project)
            return unless pbx_path && File.exist?(pbx_path)

            @project_digests[project.object_id] = digest_file(pbx_path)
            @sort_needed[project.object_id] = false
          end

          def pbxproj_path(project)
            path = project.path
            return nil unless path
            if path.to_s.end_with?('.xcodeproj')
              File.join(path.to_s, 'project.pbxproj')
            else
              path.to_s
            end
          end

          def digest_file(path)
            require 'digest'
            return nil unless File.file?(path)
            Digest::SHA256.file(path).hexdigest
          rescue StandardError
            nil
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
