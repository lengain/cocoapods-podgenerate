# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches PodsProjectWriter to support incremental + parallel project saves.
#
# v0.1.1 Optimizations:
#  1. SHA256 digest — skip sort+save for unchanged projects
#  2. Parallel save — multiple xcodeproj files saved in threads
#
# Reference: CocoaPods — lib/cocoapods/installer/xcode/pods_project_generator/pods_project_writer.rb

module Pod
  module PodGenerate
    module Patches
      module ProjectWriterPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying ProjectWriterPatch v2 (incremental + parallel save)'
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

          # ── Optimization: SHA256 skip + parallel save ──
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
        end
      end
    end
  end
end
