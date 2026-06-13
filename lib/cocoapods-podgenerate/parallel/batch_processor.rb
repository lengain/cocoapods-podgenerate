# frozen_string_literal: true

# [cocoapods-podgenerate]
# 批处理器 — 将工作项在线程池中并行分配处理。
#
# 用于将需要并行化的批量任务分配到 Concurrent::FixedThreadPool，
# 保持结果的输入顺序（通过索引数组）。
#
# v0.1.4 改进：
#   - wait_for_termination 添加超时（120s）防止死锁
#   - 移除未使用的 batch_size 和 completed 变量

require 'concurrent'
require_relative 'thread_pool'

module Pod
  module PodGenerate
    module Parallel
      module BatchProcessor
        # 在线程池中并行处理项目，保持结果的输入顺序
        #
        # @param items [Array] 要处理的项目列表
        # @param pool [Concurrent::FixedThreadPool] 线程池实例
        # @yield [item] 处理每个项目的代码块
        # @return [Array] 结果列表，顺序与输入相同（nil 表示处理失败的项目）
        def self.process(items, pool:, &block)
          return [] if items.empty?

          results = Array.new(items.size)
          mutex = Mutex.new

          items.each_with_index do |item, idx|
            pool.post do
              result = block.call(item)
              mutex.synchronize { results[idx] = result }
            rescue StandardError => e
              Pod::UI.warn "[cocoapods-podgenerate] BatchProcessor error on item #{idx}: #{e.message}"
            end
          end

          # v0.1.4: 带超时的等待
          pool.shutdown
          unless pool.wait_for_termination(Pod::PodGenerate::Parallel::ThreadPool::DEFAULT_TIMEOUT)
            Pod::UI.warn '[cocoapods-podgenerate] BatchProcessor timed out after 120s'
            pool.kill
          end

          results
        end
      end
    end
  end
end
