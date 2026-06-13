# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches PodsProjectWriter to support incremental project saves.
# Uses project.pbxproj file for change detection via SHA256 digest.
#
# Reference: CocoaPods source — lib/cocoapods/installer/xcode/pods_project_generator/pods_project_writer.rb

module Pod
  module PodGenerate
    module Patches
      module ProjectWriterPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying ProjectWriterPatch (incremental save)'
          Pod::Installer::Xcode::PodsProjectWriter.prepend(IncrementalSave)
        end

        module IncrementalSave
          def initialize(sandbox, projects, pod_target_installation_results, installation_options)
            super
            @project_digests = {}
            @projects = projects
            @sort_needed = {}
            compute_initial_digests
          end

          def save_projects(projects)
            projects.each do |project|
              if project_unchanged?(project)
                Pod::UI.message "- Skipping unchanged project #{UI.path project.path}"
                next
              end

              project.sort(:groups_position => :below) if needs_sort?(project)
              Pod::UI.message "- Writing Xcode project file to #{UI.path project.path}" do
                project.save
              end
              update_digest(project)
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
            # .xcodeproj is a directory; the actual content is in project.pbxproj
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
