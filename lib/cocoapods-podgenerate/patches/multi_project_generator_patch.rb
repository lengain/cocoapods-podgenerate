# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches MultiPodsProjectGenerator，将 PodTarget 安装并行化。
#
# 优化原理：
#   `generate_multiple_pod_projects` 启用了后，每个 pod 有自己独立的
#   .xcodeproj 文件。原实现串行遍历所有 project，逐个调用
#   `install_pod_targets`。由于每个 project 的 xcodeproj 目录不同，
#   PodTargetInstaller（创建 xcconfig、module map、脚本等文件 I/O）可以
#   安全地并行执行，无需加锁。
#
# v0.1.4 改进：
#   - Bug 修复：线程池内错误不再静默吞掉，失败时传播异常避免依赖图不完整
#   - 添加 wait_for_termination 超时（120 秒），防止死锁导致进程永久挂起
#
# 线程安全保证：
#   - 每个 project 是独立的 Xcodeproj::Project 实例（各自 .xcodeproj 目录）
#   - install_pod_targets 只修改传入的 project，不访问其他 project
#   - sandbox 读取操作是线程安全的（写操作进入不同 pod 子目录）
#   - 结果合并使用 Mutex 保护共享的 all_results Hash
#
# 参考：CocoaPods 源码
#   - lib/cocoapods/installer/xcode/multi_pods_project_generator.rb
#   - lib/cocoapods/installer/xcode/pods_project_generator.rb

require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module MultiProjectGeneratorPatch
        # 激活补丁：对 MultiPodsProjectGenerator prepend 我们的并行版本
        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying MultiProjectGeneratorPatch (parallel pod target install)'
          Pod::Installer::Xcode::MultiPodsProjectGenerator.prepend(ParallelMultiProjectGenerator)
        end

        module ParallelMultiProjectGenerator
          # 并行安装所有 pod target
          #
          # 原实现（串行）:
          #   projects_by_pod_targets.each_with_object({}) { |(p, pts), r| r.merge!(install_pod_targets(p, pts)) }
          #
          # 优化后（并行）:
          #   使用 Concurrent::FixedThreadPool，每个 project 分配一个线程
          #   并发调用 install_pod_targets，结果通过 Mutex 合并到 all_results
          #
          # @param projects_by_pod_targets [Hash{Project => Array<PodTarget>}]
          #   项目到 pod target 列表的映射
          # @return [Hash{String => TargetInstallationResult}]
          #   pod target 名称到安装结果的映射
          def install_all_pod_targets(projects_by_pod_targets)
            UI.message '- Installing Pod Targets (parallel)' do
              pool_size = compute_pool_size
              mutex = Mutex.new
              all_results = {}
              errors = [] # v0.1.4: 收集错误而不是静默吞掉

              pool = Concurrent::FixedThreadPool.new(pool_size)
              projects_by_pod_targets.each do |project, pts|
                pool.post do
                  # 每个 project 独立安装其 pod target
                  target_results = install_pod_targets(project, pts)
                  mutex.synchronize { all_results.merge!(target_results) }
                rescue StandardError => e
                  mutex.synchronize do
                    errors << [project.path, e]
                    Pod::UI.warn "[cocoapods-podgenerate] Pod target install failed for #{project.path}: #{e.message}"
                  end
                end
              end

              # v0.1.4: 带超时的等待，防止死锁
              pool.shutdown
              unless pool.wait_for_termination(Pod::PodGenerate::Parallel::ThreadPool::DEFAULT_TIMEOUT)
                Pod::UI.warn '[cocoapods-podgenerate] Pod target install timed out after 120s — forcing shutdown'
                pool.kill
              end

              # v0.1.4: 如果有任何失败，抛出异常让 CocoaPods 知道安装不完整
              unless errors.empty?
                raise Pod::Informative, "[cocoapods-podgenerate] #{errors.size} pod target(s) failed to install"
              end

              all_results
            end
          end

          private

          # 计算适合当前机器的线程池大小
          # 使用 CPU 核心数 - 1（为主线程留一个），最小 2，最大 16
          # @return [Integer]
          def compute_pool_size
            [[Etc.nprocessors - 1, 2].max, 16].min
          rescue NameError
            4 # Etc 不可用时的安全回退
          end
        end
      end
    end
  end
end
