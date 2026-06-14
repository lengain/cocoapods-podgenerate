# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches Analyzer 来缓存依赖解析结果，跳过 Molinillo 算法。
#
# Molinillo 依赖解析的时间复杂度在最坏情况下为 O(n²)（n = pod 数量），
# 对于 200+ pod 的项目需要 30-120 秒。
#
# 优化策略：
#   - 首次运行后，保存解析结果（按 TargetDefinition 分组的 pod 名→版本号映射）
#     到缓存文件
#   - 缓存键 = SHA256(Podfile.to_yaml + Podfile.lock.to_yaml + CocoaPods 版本号)
#   - 后续运行时，如果缓存命中，从 Manifest 的 specifications 重建完整 Specification
#     对象列表，完全跳过 Molinillo 解析
#
# YAML 序列化可行性说明：
#   - Specification 对象包含大量内部状态（Source、Checksum、Platform 等），
#     无法直接 YAML 序列化（会触发 Marshal.dump 或递归深度错误）
#   - 解决方案：只保存 pod_name（字符串）和 version（字符串），它们是 Ruby
#     基本类型，可以安全地序列化为 YAML
#   - 下次加载时，通过 sandbox.manifest.specifications 获取所有已安装的完整
#     Specification 对象，按名称匹配重建结果 Hash
#   - sandbox.manifest 是 Podfile.lock 的内存表示，在 pod install 开始时即加载，
#     反映上一次成功安装的状态。当 Podfile 和 lockfile 都未改变时，
#     manifest 中的 specification 与 Molinillo 将解析出的结果完全一致
#
# 线程安全：
#   - 所有操作在主线程中执行（Analyzer#resolve_dependencies 在 install! 主流程中）
#   - 文件 I/O 使用原子写入（临时文件 + rename）避免写入中断导致缓存损坏
#
# 缓存失效条件（任一满足即视为 MISS，触发完整 Molinillo 解析）：
#   - Podfile 内容发生任何变化
#   - Podfile.lock 内容发生任何变化
#   - CocoaPods 版本升级
#   - 缓存文件不存在或格式损坏
#
# 参考：CocoaPods 源码 — lib/cocoapods/installer/analyzer.rb

require 'digest'
require 'yaml'

module Pod
  module PodGenerate
    module Patches
      module AnalyzerPatch
        # 缓存文件路径（相对于 Pods 目录）
        # 放在 Pods 目录下，与其他生成物一起管理
        CACHE_FILE = '.cocoapods-resolution-cache.yaml'

        # 应用补丁入口
        # 将 CachedResolution 模块 prepend 到 Pod::Installer::Analyzer，
        # 使得 resolve_dependencies 方法先执行缓存逻辑
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying AnalyzerPatch (resolution cache)'
          Pod::Installer::Analyzer.prepend(CachedResolution)
        end

        # 缓存解析结果的模块
        # 通过 prepend 机制覆盖 Analyzer#resolve_dependencies，
        # 在 Molinillo 执行前后插入缓存读写逻辑
        module CachedResolution
          # 重写 resolve_dependencies，利用缓存跳过 Molinillo 解析
          #
          # 工作流程：
          #   1. compute_resolution_cache_key: 计算当前 Podfile + lockfile 的 SHA256 缓存键
          #   2. load_cached_result: 如果缓存命中且有效，从 Manifest 重建 specs_by_target 并返回
          #   3. super(locked_dependencies): 缓存未命中，调用原始 Molinillo 解析
          #   4. save_cached_result: 保存本次解析结果到 YAML 文件供下次使用
          #
          # @param locked_dependencies [Hash] 锁定的依赖关系，传递给原始解析器
          # @return [Hash{TargetDefinition => Array<Specification>}]
          #   每个 Podfile TargetDefinition 映射到其依赖的 Specification 对象数组
          def resolve_dependencies(locked_dependencies)
            # 步骤 1：计算缓存键（SHA256，基于 Podfile + lockfile 内容）
            cache_key = compute_resolution_cache_key(locked_dependencies)

            # 步骤 2：尝试从缓存加载并重建结果
            cached = load_cached_result(cache_key)
            if cached
              Pod::UI.message '[cocoapods-podgenerate] 解析缓存命中 - 跳过 Molinillo 解析'
              return cached
            end

            # 步骤 3：缓存未命中，执行完整的 Molinillo 依赖解析
            Pod::UI.message '[cocoapods-podgenerate] 解析缓存未命中 - 运行 Molinillo 解析'
            result = super(locked_dependencies)

            # 步骤 4：保存解析结果到缓存（只保存可序列化的名称和版本）
            save_cached_result(cache_key, result)
            result
          end

          private

          # 计算缓存键：SHA256(Podfile.to_yaml + Manifest.to_yaml + CocoaPods 版本)
          #
          # 为什么使用 to_yaml 而不是 to_s/to_hash：
          #   - to_s 返回的对象字符串表示可能包含内存地址（如 #<Podfile:0x00007f...>），
          #     在跨进程中不稳定，导致缓存永久失效
          #   - to_yaml 产出纯文本的、确定性的 YAML 序列化结果，
          #     只要 Podfile 语义不变，YAML 输出就不变
          #
          # 加入 CocoaPods 版本号的原因：
          #   - 不同版本的 CocoaPods 可能有不同的解析行为（API 变更、bug 修复）
          #   - 版本升级时自动使所有缓存失效，确保使用新版本的解析逻辑
          #
          # @param locked_deps [Hash] 锁定的依赖关系，序列化后加入键中
          # @return [String] 64 位十六进制 SHA256 摘要字符串
          def compute_resolution_cache_key(locked_deps)
            # Podfile 内容：使用 to_yaml 获得稳定的确定性序列化
            pf_content = ''
            if respond_to?(:podfile) && podfile
              pf_content = podfile.to_yaml
            end

            # Podfile.lock 内容（通过 sandbox.manifest 访问）
            # 也使用 to_yaml 确保序列化稳定性
            lockfile_content = ''
            if sandbox && sandbox.manifest
              lockfile_content = sandbox.manifest.to_yaml
            end

            # 锁定的依赖关系，使用 YAML 序列化
            locked_deps_str = locked_deps.to_yaml if locked_deps

            # 组合所有输入并计算 SHA256 哈希
            # 使用 '|' 作为分隔符避免不同输入的意外拼接
            raw = [pf_content, lockfile_content, locked_deps_str, Pod::VERSION].join('|')
            Digest::SHA256.hexdigest(raw)
          end

          # 返回缓存文件的完整绝对路径
          #
          # @return [String] 缓存文件的绝对路径（位于 Pods 目录下）
          def cache_path
            sandbox_root = sandbox.root
            File.join(sandbox_root.to_s, CACHE_FILE)
          end

          # 从 YAML 缓存文件加载并重建解析结果
          #
          # 缓存文件 YAML 格式：
          #   cache_key: <SHA256 字符串>
          #   timestamp: <时间戳，供调试参考>
          #   cocoaPods_version: <CocoaPods 版本号>
          #   pod_count: <总 pod 数量，供调试参考>
          #   targets:
          #     Pods-MyApp:           # TargetDefinition 的名称
          #       - pod_name: A       # pod 的根名称
          #         version: 1.0.0    # pod 的版本号字符串
          #     Pods-MyApp-Tests:
          #       - pod_name: B
          #         version: 2.0.0
          #
          # 重建策略（关键实现细节）：
          #   1. 从 sandbox.manifest.specifications 获取所有已安装的 Specification 对象
          #      （Manifest = Podfile.lock 的内存表示，在 pod install 开始时已加载）
          #   2. 按 pod 名称分组建立索引
          #   3. 从 podfile.target_definitions 获取 TargetDefinition 对象
          #   4. 按缓存中记录的目标→pod 关系，组装 Hash{TargetDefinition => [Spec]}
          #
          # 为什么 Manifest 中的 specs 就是正确的：
          #   缓存命中意味着 Podfile 和 Podfile.lock 都未改变，
          #   而 Manifest 反映的是上一次 pod install 成功的状态，
          #   此时 Manifest 中的 specifications 与 Molinillo 将解析出的结果一致
          #
          # @param cache_key [String] 期望的缓存键，与文件中存储的键比较验证有效性
          # @return [Hash, nil] 重建的解析结果（TargetDefinition => [Specification]），
          #   如果缓存无效、过期或损坏则返回 nil
          def load_cached_result(cache_key)
            path = cache_path
            return nil unless File.exist?(path)

            # 安全地加载 YAML，允许 Symbol 类型的反序列化
            data = YAML.safe_load(File.read(path), permitted_classes: [Symbol])
            return nil unless data.is_a?(Hash)

            # 验证缓存键匹配 — 如果不匹配说明 Podfile 或 lockfile 已变化
            return nil unless data['cache_key'] == cache_key

            cached_targets = data['targets']
            return nil unless cached_targets.is_a?(Hash) && !cached_targets.empty?

            # 步骤 1：从 Manifest 获取所有已安装的 Specification 对象
            # manifest.specifications 返回 Array<Specification>
            manifest_specs = sandbox.manifest.specifications

            # 步骤 2：按 pod 根名称建立索引
            # 注意：一个 pod 可能有多个 subspec，它们共享同一个 root.name
            # 使用 group_by 将同名 pod 的所有 spec（含 subspec）归为一组
            specs_by_name = {}
            manifest_specs.each do |spec|
              name = spec.root.name
              specs_by_name[name] ||= []
              specs_by_name[name] << spec
            end

            # 步骤 3：从 Podfile 获取 TargetDefinition 对象，按名称建立索引
            # podfile.target_definitions 包含所有抽象 target 和具体 target
            target_defs_by_name = {}
            podfile.target_definitions.each do |td|
              target_defs_by_name[td.name] = td
            end

            # 步骤 4：按缓存记录的目标→pod 关系，重建 {TargetDefinition => [Spec]}
            result = {}
            cached_targets.each do |target_name, pods_data|
              target_def = target_defs_by_name[target_name]
              next unless target_def  # 跳过缓存中存在但 Podfile 中已删除的目标

              specs = []
              pods_data.each do |pod_entry|
                pod_name = pod_entry['pod_name']
                pod_specs = specs_by_name[pod_name]
                specs.concat(pod_specs) if pod_specs
              end
              result[target_def] = specs unless specs.empty?
            end

            return nil if result.empty?
            result
          rescue StandardError => e
            # 缓存加载失败不应中断 pod install 主流程
            # 最坏情况：缓存文件损坏 → MISS → 正常 Molinillo 解析
            Pod::UI.warn "[cocoapods-podgenerate] 加载解析缓存失败: #{e.message}"
            nil
          end

          # 将 Molinillo 解析结果保存到 YAML 缓存文件
          #
          # 保存策略：
          #   - 不保存 Specification 对象（无法序列化）
          #   - 只保存 pod 名称+版本号字符串
          #   - 按 TargetDefinition 名称组织数据结构
          #   - 使用原子写入（临时文件 + rename）避免写入中断导致缓存损坏
          #
          # 原子写入步骤：
          #   1. 先写入 .tmp 临时文件
          #   2. 写入完成后 rename 到目标文件
          #   3. rename 是原子操作，避免了进程崩溃时残留损坏的缓存文件
          #
          # @param cache_key [String] 缓存键，写入文件头部供下次 load 验证
          # @param result [Hash{TargetDefinition => Array<Specification>}] Molinillo 解析结果
          def save_cached_result(cache_key, result)
            begin
              path = cache_path

              # 提取纯数据：从 Specification 对象中只取名称和版本号
              # 使用 respond_to? 安全检查确保 result 是预期的格式
              targets_data = {}
              if result.respond_to?(:each)
                result.each do |target_def, specs|
                  next unless specs.respond_to?(:map)
                  pod_list = specs.map do |spec|
                    next unless spec.respond_to?(:root) && spec.root.respond_to?(:name) &&
                                spec.respond_to?(:version)
                    {
                      'pod_name' => spec.root.name,
                      'version' => spec.version.to_s,
                    }
                  end.compact
                  pod_list.uniq! { |entry| entry['pod_name'] }
                  target_name = target_def.respond_to?(:name) ? target_def.name : target_def.to_s
                  targets_data[target_name] = pod_list unless pod_list.empty?
                end
              end

              # 组装缓存数据
              data = {
                'cache_key' => cache_key,
                'timestamp' => Time.now.to_s,
                'cocoaPods_version' => Pod::VERSION,
                'pod_count' => targets_data.values.flatten.size,
                'targets' => targets_data,
              }

              # 原子写入：先写临时文件，成功后再 rename
              tmp_path = "#{path}.tmp"
              File.write(tmp_path, YAML.dump(data))
              File.rename(tmp_path, path)
            rescue StandardError => e
              Pod::UI.warn "[cocoapods-podgenerate] 保存解析缓存失败: #{e.message}"
            end
          end
        end
      end
    end
  end
end
