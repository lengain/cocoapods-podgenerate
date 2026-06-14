# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches PodsProjectWriter 以支持增量 + 并行项目保存。
#
# 优化原理：
#   `generate_multiple_pod_projects` 启用后，每个 pod 有独立的 xcodeproj 文件，
#   每个文件的操作（清理空组、重建用户 scheme、排序、保存）天然线程安全，
#   因为不同 xcodeproj 在不同目录，不存在共享状态。
#
# v0.1.1 优化：
#   1. SHA256 摘要比对，跳过未变更项目的 sort+save
#   2. 多项目文件并行保存
#
# v0.1.2 优化：
#   3. 并行 cleanup_projects（空 group 清理）
#   4. 并行 recreate_user_schemes（scheme 文件创建）
#
# v0.1.4 修复：
#   - L1: digest_file 返回 nil 时 nil==nil 导致误跳过保存，改为只有
#         两个摘要都有效且相等时才跳过
#   - M1: wait_for_termination 加 120s 超时
#   - L2: 移除无效的 || [] 死代码
#
# 线程安全保证：
#   - 每个 xcodeproj 是独立目录，project.save 写项目名.pbxproj
#   - cleanup_single_project 只操作传入的 project 对象
#   - recreate_schemes_for_project 只操作传入的 project 对象
#   - results_by_native_target 在所有线程间只读共享（构建一次后不变）
#
# 参考：CocoaPods 源码
#   - lib/cocoapods/installer/xcode/pods_project_generator/pods_project_writer.rb

require 'digest'
require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module ProjectWriterPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying ProjectWriterPatch v4 (incremental + parallel save + parallel write)'
          Pod::Installer::Xcode::PodsProjectWriter.prepend(IncrementalAndParallelSave)
        end

        module IncrementalAndParallelSave
          # 初始化：调用原始构造器后，计算所有项目的初始 SHA256 摘要
          #
          # @param sandbox [Sandbox]
          # @param projects [Array<Project>] 所有需要管理的 Xcodeproj 项目
          # @param pod_target_installation_results [Hash] pod target 安装结果
          # @param installation_options [InstallationOptions]
          def initialize(sandbox, projects, pod_target_installation_results, installation_options)
            super
            @project_digests = {}    # project.object_id => SHA256 摘要
            @sort_needed = {}        # project.object_id => 是否需要排序
            compute_initial_digests
          end

          # 并行清理、重建 scheme、然后增量保存所有项目
          #
          # 流程:
          #   1. 并行清理每个项目的空 groups
          #   2. 并行重建 scheme（将 test target 附加到 library target）
          #   3. 执行 post-install hooks（yield）
          #   4. SHA256 增量判断 + 并行保存
          def write!
            parallel_cleanup_projects(@projects)
            parallel_recreate_user_schemes(@projects)
            yield if block_given?
            save_projects(@projects)
          end

          # 增量 + 并行保存项目
          #
          # 流程:
          #   1. 过滤: 跳过 pbxproj 内容未变的项目（SHA256 摘要比对）
          #   2. 排序: 对需要保存的项目调用 sort(:groups_position => :below)
          #   3. 保存: 多项目并行写入（每个 xcodeproj 独立目录）
          #
          # 【Bug 修复 L1】
          # 只有当 old_digest 和 current_digest 都非 nil 且相等时才跳过。
          # 如果任一为 nil（例如文件不可读），一律重新保存以确保项目完整性。
          #
          # @param projects [Array<Project>] 要保存的项目列表
          def save_projects(projects)
            to_save = projects.select do |project|
              old = @project_digests[project.object_id]
              cur = digest_pbxproj(project)
              if old && cur && old == cur
                Pod::UI.message "- Skipping unchanged project #{UI.path project.path}"
                false
              else
                true
              end
            end
            return if to_save.empty?

            # 排序（串行 — sort 操作轻量，并行开销反而更大）
            to_save.each { |p| p.sort(:groups_position => :below) if needs_sort?(p) }

            # 并行保存
            if to_save.size > 1
              Pod::UI.message "- Saving #{to_save.size} projects in parallel"
              threads = to_save.map do |project|
                Thread.new do
                  Pod::UI.message "- Writing Xcode project file to #{UI.path project.path}"
                  project.save
                  update_digest(project)
                rescue StandardError => e
                  Pod::UI.warn "[cocoapods-podgenerate] Parallel save error: #{e.message}"
                end
              end
              threads.each(&:join)
            else
              project = to_save.first
              Pod::UI.message "- Writing Xcode project file to #{UI.path project.path}"
              project.save
              update_digest(project)
            end
          end

          private

          # ── 并行清理项目空 groups ──

          # 移除每个项目中为空的 pods、support_files、development_pods、dependencies groups
          #
          # 每个 project 独立，使用 Concurrent::FixedThreadPool 并行执行。
          # 如果 concurrent-ruby 不可用（NameError），回退到串行处理。
          def parallel_cleanup_projects(projects)
            pool_size = compute_pool_size
            Pod::UI.message "- Cleaning up #{projects.size} projects (pool: #{pool_size})"

            pool = begin
              Concurrent::FixedThreadPool.new(pool_size)
            rescue NameError
              nil # concurrent-ruby 不可用，回退到串行
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
              pool.wait_for_termination(Pod::PodGenerate::Parallel::ThreadPool::DEFAULT_TIMEOUT) || pool.kill
            else
              # 串行回退
              projects.each { |p| cleanup_single_project(p) }
            end
          end

          # 清理单个项目的空 groups
          def cleanup_single_project(project)
            [project.pods, project.support_files_group,
             project.development_pods, project.dependencies_group].each do |group|
              group.remove_from_project if group.respond_to?(:empty?) && group.empty?
            end
          end

          # ── 并行重建用户 scheme ──

          # 为所有项目重建 scheme 文件，将 test target 附加到 library target
          #
          # results_by_native_target 在所有线程间是只读共享缓存，
          # 每个线程读取同一个 Hash 但从不修改它 → 线程安全。
          def parallel_recreate_user_schemes(projects)
            library_product_types = [:framework, :dynamic_library, :static_library]

            # 预构建 native target → InstallationResult 的查找缓存（只读、线程安全）
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
              pool.wait_for_termination(Pod::PodGenerate::Parallel::ThreadPool::DEFAULT_TIMEOUT) || pool.kill
            else
              projects.each do |project|
                recreate_schemes_for_project(project, library_product_types, results_by_native_target)
              end
            end
          end

          # 为单个项目重建 scheme
          #
          # @param project [Project] Xcodeproj 项目
          # @param library_product_types [Array<Symbol>] 需要添加 test target 的 library 类型
          # @param results_by_native_target [Hash] native_target => InstallationResult 缓存
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

          # 构建 native_target → InstallationResult 查找缓存
          def build_native_target_cache
            cache = {}
            @pod_target_installation_results.each do |_, result|
              cache[result.native_target] = result if result.respond_to?(:native_target)
            end
            cache
          end

          # ── SHA256 摘要工具方法 ──

          # 计算所有项目的初始 SHA256 摘要
          def compute_initial_digests
            @projects.each { |p| update_digest(p) }
            @projects.each { |p| @sort_needed[p.object_id] = true }
          end

          # 是否需要排序（首次写入总是需要）
          def needs_sort?(project)
            @sort_needed[project.object_id] != false
          end

          # 更新项目的 SHA256 摘要缓存
          def update_digest(project)
            digest = digest_pbxproj(project)
            return unless digest
            @project_digests[project.object_id] = digest
            @sort_needed[project.object_id] = false
          end

          # 计算指定项目的 pbxproj 文件的 SHA256 摘要
          #
          # @param project [Project] Xcodeproj 项目
          # @return [String, nil] SHA256 十六进制字符串，或 nil（文件不存在/不可读）
          def digest_pbxproj(project)
            path = project.path
            return nil unless path
            pbx_path = path.to_s.end_with?('.xcodeproj') ? File.join(path.to_s, 'project.pbxproj') : path.to_s
            return nil unless File.file?(pbx_path)
            Digest::SHA256.file(pbx_path).hexdigest
          rescue StandardError
            nil
          end

          # 计算线程池大小
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
