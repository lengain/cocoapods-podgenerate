# frozen_string_literal: true

# [cocoapods-podgenerate]
# 线程池工具模块 — 提供跨所有补丁共享的线程池大小计算和超时配置。

require 'etc'

module Pod
  module PodGenerate
    module Parallel
      module ThreadPool
        # 默认的线程池等待超时（秒）
        DEFAULT_TIMEOUT = 120

        class << self
          # 计算适合当前机器的线程池大小
          # 使用 nproc - 1（为主线程留一个核心），最小 2，最大 16
          # @return [Integer] 推荐的线程池大小
          def pool_size
            [[Etc.nprocessors - 1, 2].max, 16].min
          rescue NameError
            4
          end
        end
      end
    end
  end
end
