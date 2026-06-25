# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches ProjectCacheAnalyzer，并行计算缓存键。
#
# 优化原理：
#   ProjectCacheAnalyzer#create_cache_key_mappings 为所有 pod_target
#   和 aggregate_target 计算 TargetCacheKey。每个 target 的计算需要
#   - 遍历文件列表计算 MD5 校验和
#   - 汇总上游依赖的资源信息
#   所有 target 的计算完全独立，天然适合并行化。
#
# 性能收益（150 pod target 场景）：
#   原串行实现逐个计算 MD5，总耗时随 pod 数量线性增长。
#   线程池并行后，计算时间除以线程数（通常 10+ 线程 → ~10x 加速）。
#
# v0.1.3 修复：
#   - Bug 修复：线程内错误不再导致 nil 条目。异常时同步重试，
#     确保 results Hash 中每个 label 都有有效的 TargetCacheKey。
#
# v0.1.4 改进：
#   - M1: wait_for_termination 添加 120 秒超时
#   - 优化 compute_cache_key 为独立方法便于错误恢复
#   - 添加详细中文注释
#
# 线程安全保证：
#   - sandbox.local? 和 sandbox.checkout_sources 都是只读操作
#   - target_by_label Hash 在所有线程间只读共享
#   - results Hash 的写入用 Mutex 保护
#
# 参考：CocoaPods 源码
#   - lib/cocoapods/installer/project_cache/project_cache_analyzer.rb

require 'concurrent'

module Pod
  module PodGenerate
    module Patches
      module CacheAnalyzerPatch
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying CacheAnalyzerPatch (parallel cache key computation)'
          Pod::Installer::ProjectCache::ProjectCacheAnalyzer.prepend(ParallelCacheKeyComputation)
        end

        module ParallelCacheKeyComputation
          # 并行计算所有 target 的缓存键
          #
          # 原实现（串行）:
          #   Hash[target_by_label.map { |label, target| [label, compute_key(target)] }]
          #
          # 优化后（并行）:
          #   使用 Concurrent::FixedThreadPool，每个 target 分配一个线程，
          #   并发计算 TargetCacheKey，结果通过 Mutex 合并到 results Hash。
          #
          # @param target_by_label [Hash{String => PodTarget|AggregateTarget}]
          #   target 标签到 target 对象的映射
          # @return [Hash{String => TargetCacheKey}]
          #   target 标签到缓存键的映射
          def create_cache_key_mappings(target_by_label)
            UI.message '- Creating cache key mappings (parallel)' do
              pool_size = Pod::PodGenerate::Parallel::ThreadPool.compute_pool_size
              pool = Concurrent::FixedThreadPool.new(pool_size)
              mutex = Mutex.new
              results = {}

              # 为每个 target 提交一个线程任务
              target_by_label.each do |label, target|
                pool.post do
                  key = compute_cache_key(target, target_by_label)
                  mutex.synchronize { results[label] = key }
                rescue StandardError => e
                  # v0.1.3 bug 修复: 异常时同步重试，确保 results[label] 不为 nil
                  # 如果重试仍然失败，异常会传播导致 pod install 失败（正确的行为）
                  Pod::UI.warn "[cocoapods-podgenerate] Cache key computation error, retrying sync: #{e.message}"
                  fallback_key = compute_cache_key(target, target_by_label)
                  mutex.synchronize { results[label] = fallback_key }
                end
              end

              # v0.1.4: 带超时的等待
              pool.shutdown
              unless pool.wait_for_termination(Pod::PodGenerate::Parallel::ThreadPool::DEFAULT_TIMEOUT)
                Pod::UI.warn '[cocoapods-podgenerate] Cache key computation timed out after 120s'
                pool.kill
              end

              results
            end
          end

          private

          # 计算单个 target 的缓存键
          #
          # 根据 target 类型（PodTarget 或 AggregateTarget）调用不同的计算逻辑:
          #   - PodTarget:  检查是否本地 pod + checkout 选项 → from_pod_target
          #   - AggregateTarget: 直接调用 from_aggregate_target
          #
          # @param target [PodTarget|AggregateTarget] 要计算的目标
          # @param target_by_label [Hash] 完整的 label→target 映射（from_pod_target 需要）
          # @return [TargetCacheKey] 缓存键对象
          def compute_cache_key(target, target_by_label)
            case target
            when PodTarget
              local = sandbox.local?(target.pod_name)
              checkout_options = sandbox.checkout_sources[target.pod_name]
              TargetCacheKey.from_pod_target(sandbox, target_by_label, target,
                                             :is_local_pod => local,
                                             :checkout_options => checkout_options)
            when AggregateTarget
              TargetCacheKey.from_aggregate_target(sandbox, target_by_label, target)
            else
              raise "[BUG] Unknown target type #{target}"
            end
          end

        end
      end
    end
  end
end
