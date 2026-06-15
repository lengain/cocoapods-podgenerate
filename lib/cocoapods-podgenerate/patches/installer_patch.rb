# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches Pod::Installer 和 PodsProjectGenerator，优化步骤 3/4。
#
# 优化原理：
#   CocoaPods 内置了 incremental_installation 和 generate_multiple_pod_projects
#   两个选项。本补丁强制启用这两个选项，并在其基础上进一步增强：
#     - 完全无变更时跳过整个项目生成
#     - 并行执行 PodTargetIntegrator
#     - 并行配置 scheme 文件
#     - 修复快速跳过路径的 ivars 和 hooks 缺失问题
#
# v0.1.1 优化:
#   1. 强制启用 incremental_installation + generate_multiple_pod_projects
#   2. 完全无变更时跳过项目生成
#   3. 并行化 PodTargetIntegrator 集成
#
# v0.1.2 优化:
#   4. 并行化 configure_schemes（跨项目）
#
# v0.1.4 修复:
#   - C2: 快速跳过路径设置缺失的 @pods_project/@pod_target_subprojects/@generated_projects
#         并确保 run_podfile_post_install_hooks 被调用（即使在跳过路径上）
#   - H1: 跳过路径不再调用 update_project_cache（@target_installation_results 在跳过路径
#         上始终为 nil，回退到空 InstallationResults 会清除 metadata_cache 导致下次全量重建）
#   - L3: parallel_configure_schemes 用 defined?(Concurrent::FixedThreadPool) 替代
#         宽泛的 rescue NameError（NameError 可能吞掉无关的未定义常量/变量错误）
#   - M1: wait_for_termination 使用 ThreadPool::DEFAULT_TIMEOUT
#   - M3: integrate_targets 改用 Concurrent::FixedThreadPool（限制并发数，避免 200 线程）
#
# 线程安全保证：
#   - configure_schemes: 每个 project 独立 xcodeproj → 并行安全
#   - integrate_targets: 每个 PodTargetIntegrator 操作独立的 target → 并行安全
#
# 参考：CocoaPods 源码
#   - lib/cocoapods/installer.rb
#   - lib/cocoapods/installer/xcode/pods_project_generator.rb

require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module InstallerPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying InstallerPatch v4'
          Pod::Installer.prepend(ForceIncrementalInstall)
          Pod::Installer::Xcode::PodsProjectGenerator.prepend(ParallelInstall)
        end

        # ── 优化 1: 强制启用增量安装模式 ──
        #
        # 在 install! 入口处设置 installation_options，强制启用:
        #   - incremental_installation:   只重新生成有变更的 target
        #   - generate_multiple_pod_projects: 每个 pod 独立 xcodeproj
        #
        # 这两个选项是 CocoaPods 内置的（默认关闭），我们通过 monkey-patch
        # 在 super 之前设置，对所有后续流程生效。
        module ForceIncrementalInstall
          def install!
            installation_options.incremental_installation = true
            installation_options.generate_multiple_pod_projects = true
            super
          end

          # ── 优化 2: 完全无变更时跳过项目生成 + C2/H1 修复 ──
          #
          # 原流程即使没有任何 target 变更，create_and_save_projects 仍会被调用，
          # 执行大量 file I/O 操作。本方法在 analyze_project_cache 之后检查:
          #   如果 pod_targets_to_generate 和 aggregate_targets_to_generate
          #   都为空（即没有任何 target 需要重新生成），则:
          #     1. 跳过 create_and_save_projects（pod 项目已在磁盘上，内容未变）
          #     2. 仍执行 SandboxDirCleaner（清理可能被移除的 pod 的残留文件）
          #     3. 仍调用 update_project_cache（保持缓存时间戳最新）
          #     4. 仍调用 run_podfile_post_install_hooks（Podfile hook 不能跳过）
          #
          # v0.1.4 修复 (C2):
          #   - 设置 @pods_project = nil, @pod_target_subprojects = [],
          #     @generated_projects = []（避免下游引用 nil）
          #   - 调用 run_podfile_post_install_hooks（之前被跳过导致 hook 静默丢失）
          #
          # v0.1.4 修复 (H1):
          #   - 使用上次的 @target_installation_results 更新缓存
          #     （而非空的 InstallationResults，避免清除 metadata_cache）
          def generate_pods_project
            stage_sandbox(sandbox, pod_targets)

            cache_analysis_result = analyze_project_cache
            ptg = cache_analysis_result.pod_targets_to_generate
            atg = cache_analysis_result.aggregate_targets_to_generate

            if ptg.empty? && (atg.nil? || atg.empty?)
              Pod::UI.puts "[cocoapods-podgenerate] No changes — skipping project generation"

              # C2 修复: 初始化所有实例变量（避免下游代码获得 nil）
              @generated_aggregate_targets = aggregate_targets
              @generated_pod_targets = []
              # 修复: 创建空项目替代 nil，避免 post-install hooks 中
              # installer.pods_project 返回 nil 导致 .targets 等调用崩溃
              # （例如 Flutter podhelper.rb 访问 pods_project.targets）
              @pods_project = Pod::Project.new(sandbox.project_path)
              @pod_target_subprojects = []
              @generated_projects = [@pods_project]

              # C2 修复: 确保 post-install hooks 被调用
              run_podfile_post_install_hooks

              # 清理沙盒中残留的文件
              Pod::Installer::SandboxDirCleaner.new(sandbox, pod_targets, aggregate_targets).clean!

              # H1 修复: 当没有目标需要生成时，跳过 update_project_cache 调用
              # @target_installation_results 仅在 create_and_save_projects 内设置，
              # 在跳过路径上始终为 nil，回退到空 InstallationResults.new({}, {})
              # 会导致 metadata_cache 中所有 pod target 的安装结果被清除，
              # 下次运行时触发全量重建（cache 损坏）。
              # 跳过路径的正确行为：不更新任何缓存，因为没有任何变化，
              # 已有的缓存状态仍然有效。
              return
            end

            # 正常路径: 有 target 需要重新生成
            ptg.each do |pod_target|
              pod_target.build_headers.implode_path!(pod_target.headers_sandbox)
              sandbox.public_headers.implode_path!(pod_target.headers_sandbox)
            end

            create_and_save_projects(ptg, atg,
              cache_analysis_result.build_configurations, cache_analysis_result.project_object_version)
            Pod::Installer::SandboxDirCleaner.new(sandbox, pod_targets, aggregate_targets).clean!
            update_project_cache(cache_analysis_result, target_installation_results)
          end

          # ── 优化 3+4: 项目生成 + 并行 configure_schemes ──
          #
          # 完全覆盖原 create_and_save_projects 方法，添加并行 configure_schemes。
          # 流程:
          #   1. 创建 generator → 调用 generate!（并行安装 pod targets）
          #   2. 设置实例变量（@pods_project 等）
          #   3. UUID 预测 + 稳定化
          #   4. 创建 writer → 并行清理/重建 scheme/保存
          #   5. 并行 configure_schemes（每个 project 独立）
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
              @generated_projects = ([pods_project] + pod_target_subprojects).compact
              @generated_pod_targets = pod_targets_to_generate
              @generated_aggregate_targets = aggregate_targets_to_generate || []
              projects_by_pod_targets = pod_project_generation_result.projects_by_pod_targets

              predictabilize_uuids(generated_projects) if installation_options.deterministic_uuids?
              stabilize_target_uuids(generated_projects)

              projects_writer = Pod::Installer::Xcode::PodsProjectWriter.new(sandbox, generated_projects,
                                                             target_installation_results.pod_target_installation_results,
                                                             installation_options)

              # 解析跨项目依赖：当 generate_multiple_pod_projects 启用后，
              # 主项目的 aggregate target 通过 PBXContainerItemProxy 引用子项目的 pod target。
              # Xcodeproj 无法解析这些跨项目引用，PBXTargetDependency#target 返回 nil。
              # 这会导致递归遍历依赖链的工具（如 Flutter podhelper.rb 的
              # depends_on_flutter）在访问 nil.target 时崩溃。
              # 解决方法：在 post-install hooks 运行前，将子项目 target 的引用
              # 直接挂载到主项目的 PBXTargetDependency.target 上。
              resolve_cross_project_dependencies

              projects_writer.write! do
                run_podfile_post_install_hooks
              end

              # 并行 configure_schemes（多项目时）
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

          # 解析跨项目 target 依赖关系
          #
          # generate_multiple_pod_projects 启用时，每个 pod target 位于独立的
          # .xcodeproj 子项目中。主项目（Pods.xcodeproj）中的 aggregate target
          # 通过 PBXTargetDependency + PBXContainerItemProxy 引用子项目中的目标。
          # Xcodeproj 在读取主项目时不会自动加载子项目，因此
          # PBXTargetDependency#target 对于跨项目引用返回 nil。
          #
          # 在 post-install hooks 执行前，将子项目中实际的 target 对象关联到
          # 主项目的 PBXTargetDependency.target 上，使得依赖链遍历可以正常工作。
          # 这对于 Flutter podhelper.rb 的 depends_on_flutter 递归函数尤为重要。
          #
          # v0.1.9 改进：同时解析子项目 target 的跨项目依赖
          # 因为 post-install hooks 可能遍历所有 generated_projects 的 targets，
          # 不仅限于主项目（如 Flutter 新版 podhelper.rb 遍历所有子项目）。
          def resolve_cross_project_dependencies
            return unless @generated_projects && !@generated_projects.empty?
            Pod::UI.message "[cocoapods-podgenerate] Resolving cross-project deps across #{@generated_projects.size} projects"

            # 构建全局 UUID → target 查找表（来自所有项目，包括主项目）
            all_targets = {}
            @generated_projects.each do |project|
              project.targets.each do |target|
                all_targets[target.uuid] = target
              end
            end

            if all_targets.empty?
              Pod::UI.message '[cocoapods-podgenerate] No targets found in generated_projects — skipping cross-project resolution'
              return
            end

            resolved = 0
            # 遍历所有项目（主项目 + 子项目），解析它们的跨项目依赖
            @generated_projects.each do |project|
              project.targets.each do |target|
                target.dependencies.each do |dependency|
                  # 已解析的（同一项目内）跳过
                  next if dependency.target
                  # 无 proxy 引用说明不是跨项目依赖，也跳过
                  next unless dependency.target_proxy

                  remote_uuid = dependency.target_proxy.remote_global_id_string
                  next unless remote_uuid

                  remote_target = all_targets[remote_uuid]
                  next unless remote_target

                  dependency.target = remote_target
                  resolved += 1
                end
              end
            end

            return unless resolved > 0

            Pod::UI.message "[cocoapods-podgenerate] Resolved #{resolved} cross-project target dependencies"
          end

          # ── 并行配置 scheme ──
          #
          # 每个 scheme 文件是独立的 .xcscheme，存储在不同 xcodeproj 的
          # xcuserdata 目录中。每个 project 完全独立 → 无锁并行。
          def parallel_configure_schemes(projects_by_pod_targets, generator, generation_result)
            pool_size = [[Etc.nprocessors - 1, 2].max, 16].min
            Pod::UI.message "- Configuring schemes across #{projects_by_pod_targets.size} projects (pool: #{pool_size})"

            # L3 修复: defined? 精确检查类可用性，替代 rescue NameError
            unless defined?(Concurrent::FixedThreadPool)
              # 回退到顺序执行（concurrent-ruby 中的 FixedThreadPool 不可用）
              projects_by_pod_targets.each do |project, pts|
                generator.configure_schemes(project, pts, generation_result)
              end
              return
            end

            pool = Concurrent::FixedThreadPool.new(pool_size)
            projects_by_pod_targets.each do |project, pts|
              pool.post do
                generator.configure_schemes(project, pts, generation_result)
              rescue StandardError => e
                Pod::UI.warn "[cocoapods-podgenerate] Scheme configuration error: #{e.message}"
              end
            end
            pool.shutdown
            unless pool.wait_for_termination(Pod::PodGenerate::Parallel::ThreadPool::DEFAULT_TIMEOUT)
              Pod::UI.warn '[cocoapods-podgenerate] Scheme configuration timed out'
              pool.kill
            end
          end
        end

        # ── 优化 3: 并行化 PodTargetIntegrator（修复 M3）──
        #
        # PodTargetIntegrator 为每个 pod target 添加脚本构建阶段
        # （如 embed frameworks、copy resources）。每个 integrator 操作
        # 独立的 target，无共享状态 → 并行安全。
        #
        # v0.1.4 修复 (M3): 使用 Concurrent::FixedThreadPool（限制并发数）
        #   替代原来的裸 Thread.new（可能同时创建 200+ 线程导致资源耗尽）
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

            if pods_to_integrate.size <= 1
              # 单 target: 直接调用，无需线程开销
              Pod::Installer::Xcode::PodsProjectGenerator::PodTargetIntegrator.new(
                pods_to_integrate.first, :use_input_output_paths => use_io_paths
              ).integrate!
              return
            end

            # 多 target: 使用线程池并行集成（M3 修复）
            pool_size = [[Etc.nprocessors - 1, 2].max, 16].min
            pool = Concurrent::FixedThreadPool.new(pool_size)

            pods_to_integrate.each do |result|
              pool.post do
                Pod::Installer::Xcode::PodsProjectGenerator::PodTargetIntegrator.new(
                  result, :use_input_output_paths => use_io_paths
                ).integrate!
              rescue StandardError => e
                Pod::UI.warn "[cocoapods-podgenerate] Integrate error: #{e.message}"
              end
            end

            pool.shutdown
            unless pool.wait_for_termination(Pod::PodGenerate::Parallel::ThreadPool::DEFAULT_TIMEOUT)
              Pod::UI.warn '[cocoapods-podgenerate] Target integration timed out'
              pool.kill
            end
          end
        end
      end
    end
  end
end
