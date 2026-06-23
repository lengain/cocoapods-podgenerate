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

            # ── 本地开发 pod 文件级变更检测 ──
            # CocoaPods 的 TargetCacheKey 使用 spec attributes_hash（如
            # source_files 的 glob 模式字符串）做哈希，不检查 glob 展开后的
            # 实际文件列表。当本地开发 pod（:path）中源文件有增删时，
            # glob 模式不变 → cache key 不变 → ptg 为空 → "No changes" 跳过。
            # 解决方法：为每个开发 pod 计算当前源文件列表的 SHA256，
            # 与上次运行的清单比较，有差异时强制加入 ptg。
            if ptg.empty? && (atg.nil? || atg.empty?)
              unless sandbox.development_pods.empty?
                dev_changed = detect_dev_pod_file_changes
                unless dev_changed.empty?
                  Pod::UI.puts "[cocoapods-podgenerate] Dev pod files changed: #{dev_changed.map(&:pod_name).join(', ')} — forcing regeneration"
                  ptg = dev_changed
                end
              end
            end

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

              # 跳过路径修复: touch Pods project.pbxproj 让 Xcode 感知到变化
              # 否则 Xcode 的 Dynamic Project Reloading 不会触发
              pods_pbxproj = File.join(sandbox.project_path.to_s, 'project.pbxproj')
              if File.file?(pods_pbxproj)
                FileUtils.touch(pods_pbxproj)
              end

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
              # 安全保护：某些 CocoaPods 配置/版本下 project 可能为 nil
              # 创建空项目降级，避免 post-install hook 中 nil.targets 崩溃
              # 参考：v0.1.11 — undefined method 'targets' for nil
              unless @pods_project
                Pod::UI.message '[cocoapods-podgenerate] pods_project is nil — creating empty fallback'
                @pods_project = Pod::Project.new(sandbox.project_path)
              end
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

          # ── 本地开发 pod 文件级变更检测 ──
          #
          # CocoaPods 的 TargetCacheKey 使用 pod_target.root_spec.attributes_hash
          # 作为缓存键的一部分。attributes_hash 中包含 source_files 等 glob 模式
          # 字符串（如 "lib/**/*.rb"），而不是实际展开后的文件列表。
          # 当本地开发 pod 的源文件在文件系统层面发生增删时，glob 模式不变，
          # 缓存键也就不会变化，导致 "No changes — skipping project generation"
          # 漏掉文件级变更。
          #
          # 解决方法：为每个开发 pod 维护一个 SHA256 清单文件，记录其 source_files
          # glob 展开后的实际文件列表的哈希值。每次 pod install 时重新计算并比较。
          # 清单存储在 Pods/.cocoapods-podgenerate-devpod-manifest.yaml 中。
          DEV_POD_FILE_MANIFEST = '.cocoapods-podgenerate-devpod-manifest.yaml'

          # 检测开发 pod 中源文件是否有增删
          # 返回需要重新生成的 PodTarget 数组
          def detect_dev_pod_file_changes
            dev_pods = sandbox.development_pods
            return [] if dev_pods.empty?

            manifest_path = File.join(sandbox.root.to_s, DEV_POD_FILE_MANIFEST)

            # 读取上次记录的 hash 值
            previous = {}
            if File.exist?(manifest_path)
              begin
                data = YAML.safe_load(File.read(manifest_path))
                previous = data if data.is_a?(Hash)
              rescue => e
                Pod::UI.warn "[cocoapods-podgenerate] Failed to read dev pod manifest: #{e.message}"
              end
            end

            current = {}
            changed = []

            pod_targets.each do |pt|
              name = pt.pod_name
              next unless dev_pods.key?(name)

              current[name] = compute_dev_pod_file_digest(pt)
              if previous[name] != current[name]
                changed << pt
              end
            end

            # 持久化当前清单
            begin
              File.write(manifest_path, YAML.dump(current))
            rescue => e
              Pod::UI.warn "[cocoapods-podgenerate] Failed to write dev pod manifest: #{e.message}"
            end

            changed
          end

          # 计算开发 pod 当前源文件列表的 SHA256
          # 使用 podspec 中的 source_files/headers glob 模式，
          # 在文件系统层面展开后对相对路径排序做哈希。
          # @return [String] 十六进制 SHA256（空文件列表则是空字符串哈希）
          def compute_dev_pod_file_digest(pod_target)
            pod_name = pod_target.pod_name
            pod_dir = sandbox.pod_dir(pod_name)
            return '' unless pod_dir && File.directory?(pod_dir)

            pod_dir_str = pod_dir.to_s
            files = []

            pod_target.spec_consumers.each do |consumer|
              patterns = []
              patterns.concat(Array(consumer.source_files))
              patterns.concat(Array(consumer.public_header_files))
              patterns.concat(Array(consumer.private_header_files))

              patterns.each do |pattern|
                full_pattern = File.join(pod_dir_str, pattern)
                Dir.glob(full_pattern).each do |f|
                  next unless File.file?(f)
                  files << f.sub("#{pod_dir_str}/", '')
                end
              end
            end

            Digest::SHA256.hexdigest(files.uniq.sort.join("\n"))
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
