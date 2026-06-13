# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches Pod::Project，将 pod_group 查找从 O(n) 优化为 O(1)。
#
# 优化原理：
#   原始 `pod_group(pod_name)` 每次调用都执行:
#     pod_groups.find { |group| group.name == pod_name }
#   这是 O(n) 的线性扫描（n = pod 数量）。
#
#   在项目生成过程中，pod_group 被调用 3-5 次/pod（从
#   FileReferencesInstaller、PodTargetInstaller 的不同位置调用）。
#   对于 200+ pod 的项目，这意味着 600-1000 次线性扫描，
#   每次扫描 200 个元素 → ~120k-200k 次比较。
#
# 修复策略：
#   1. 首次调用 pod_group 时，构建 Hash 缓存（O(n) 一次性成本）
#   2. 后续调用直接用 cached_hash[pod_name]，O(1) 查找
#   3. 调用 add_pod_group（添加新 pod group）时，清除缓存强制下次重建
#   4. 使用 `||=` 懒初始化缓存（只有第一次调用时才构建）
#
# 线程安全：
#   所有操作在主线程的 install! 流程中执行，无并发访问。
#
# 参考：CocoaPods 源码 — lib/cocoapods/project.rb

module Pod
  module PodGenerate
    module Patches
      module ProjectPatch
        # 激活补丁：对 Pod::Project prepend 缓存版本
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying ProjectPatch (pod_group hash cache)'
          Pod::Project.prepend(CachedPodGroup)
        end

        module CachedPodGroup
          # O(1) 查找 pod_group
          #
          # 首次调用时通过 build_pod_group_cache 构建 Hash 缓存，
          # 后续调用直接从缓存中查找。缓存键为 pod_name，值为 PBXGroup。
          #
          # @param pod_name [String] pod 名称
          # @return [PBXGroup, nil] 对应的 group，或 nil（pod 不存在）
          def pod_group(pod_name)
            @pod_group_cache ||= build_pod_group_cache
            @pod_group_cache[pod_name]
          end

          # 添加新 pod group 时清除缓存
          #
          # 原始方法在 main_group 或 pods/development_pods group 下
          # 创建新的 PBXGroup。由于 project 结构发生了变化，
          # 我们需要清除缓存，让下一次 pod_group 调用重新构建。
          #
          # @param pod_name [String] pod 名称
          # @param path [String] pod 路径
          # @param development [Boolean] 是否为开发 pod
          # @param absolute [Boolean] 是否为绝对路径
          # @return [PBXGroup] 新创建的 group
          def add_pod_group(pod_name, path, development = false, absolute = false)
            group = super
            @pod_group_cache = nil if defined?(@pod_group_cache)
            group
          end

          private

          # 构建 pod_name → PBXGroup 的 Hash 缓存
          #
          # 遍历 pods group 和 development_pods group 下的所有子 group，
          # 以 group.name 为键构建查找表。这是一个 O(n) 操作，但只执行一次。
          #
          # @return [Hash{String => PBXGroup}]
          def build_pod_group_cache
            cache = {}
            pod_groups.each do |group|
              cache[group.name] = group
            end
            cache
          end
        end
      end
    end
  end
end
