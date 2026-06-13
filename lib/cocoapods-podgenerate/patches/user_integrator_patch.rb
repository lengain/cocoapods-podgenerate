# frozen_string_literal: true

# [cocoapods-podgenerate]
# Monkey-patches UserProjectIntegrator to parallelize and optimize the
# "Integrating client project" step (step 4 of pod install).
#
# v0.1.1:
# 1. Parallelizes integrate_user_targets using threads
# 2. Parallelizes save_projects using threads
#
# v0.1.2:
# 3. Parallelizes warn_about_xcconfig_overrides using threads
#
# Reference: CocoaPods source
#   - lib/cocoapods/installer/user_project_integrator.rb

require 'concurrent'
require 'etc'

module Pod
  module PodGenerate
    module Patches
      module UserIntegratorPatch
        IGNORED_KEYS = %w(CODE_SIGN_IDENTITY).freeze
        INHERITED_FLAGS = %w($(inherited) ${inherited}).freeze

        def self.apply
          Pod::UI.message '[cocoapods-podgenerate] Applying UserIntegratorPatch v2 (parallel client integration + xcconfig warnings)'
          Pod::Installer::UserProjectIntegrator.prepend(ParallelIntegration)
        end

        module ParallelIntegration
          # ── Optimization 1: Parallel integrate_user_targets ──
          # 集成用户项目中的所有 Pod target（添加构建阶段、修改配置等）。
          #
          # 【竞态条件修复 H2】
          # 多个 AggregateTarget 可能属于同一个 Xcodeproj::Project 文件
          # （例如同一个 .xcodeproj 中包含多个 native target）。
          # TargetIntegrator#integrate! 会修改项目（添加 build phases、修改
          # configurations），如果两个线程同时修改同一个 Xcodeproj::Project 对象，
          # 就会产生竞态条件，导致 pbxproj 文件损坏。
          #
          # 修复策略：
          #   1. 按 user_project 将所有 target 分组
          #   2. 同一个项目内的 target → 串行集成（避免竞态）
          #   3. 不同项目之间 → 并行集成（利用多核性能）
          def integrate_user_targets
            target_integrators = targets_to_integrate.sort_by(&:name).map do |target|
              Pod::Installer::UserProjectIntegrator::TargetIntegrator.new(target, :use_input_output_paths => use_input_output_paths?)
            end

            return if target_integrators.empty?
            return target_integrators.each(&:integrate!) if target_integrators.size <= 1

            # 按 user_project 分组：同一项目的 target 共享同一个 Xcodeproj::Project 对象
            groups = target_integrators.group_by { |ti| ti.send(:target).user_project }

            if groups.size <= 1
              # 所有 target 都属于同一项目 → 串行执行，避免竞态条件
              target_integrators.each(&:integrate!)
            else
              # 不同项目 → 跨组并行，组内串行（同一项目内只有一个线程在修改）
              Pod::UI.message "- Integrating #{target_integrators.size} targets across #{groups.size} projects in parallel"
              threads = groups.map do |project, integrators|
                Thread.new do
                  integrators.each(&:integrate!)
                end
              end
              threads.each(&:join)
            end
          end

          # ── Optimization 2: Parallel save_projects ──
          # 保存修改后的用户项目文件。
          #
          # 使用并行线程保存多个 Xcodeproj 项目以提高性能。
          # 脏项目调用 project.save 写入 pbxproj，非脏项目则 touch pbxproj
          # 以更新文件修改时间（确保增量构建工具能正确检测变更）。
          # FileUtils.touch 操作用 Mutex 保护，因为 touch 不是线程安全的。
          def save_projects(projects)
            projects = projects.uniq

            if projects.size <= 1
              projects.each do |project|
                if project.dirty?
                  project.save
                else
                  FileUtils.touch(project.path + 'project.pbxproj')
                end
              end
              return
            end

            Pod::UI.message "- Saving #{projects.size} user projects in parallel"
            mutex = Mutex.new
            threads = projects.map do |project|
              Thread.new do
                begin
                  if project.dirty?
                    project.save
                  else
                    mutex.synchronize do
                      FileUtils.touch(project.path + 'project.pbxproj')
                    end
                  end
                rescue StandardError => e
                  Pod::UI.warn "[cocoapods-podgenerate] Project save error: #{e.message}"
                end
              end
            end
            threads.each(&:join)
          end

          # ── Optimization 3: Parallel warn_about_xcconfig_overrides ──
          # 检查并警告用户项目中 xcconfig 构建设置的覆盖情况。
          #
          # 通过 prepend 覆盖原始方法，在 integrate! 内部被自动调用。
          # 使用 Concurrent::FixedThreadPool 线程池并行检查多个 target，
          # 池大小由 compute_pool_size 计算（CPU 核心数 - 1，范围 2..16）。
          # 如果 NameError（例如 concurrent-ruby 不可用），回退到串行执行。
          #
          # 注意：此方法操作的是 targets_to_integrate（AggregateTarget 数组），
          # 不同 target 属于不同项目（或部分属于同一项目），但由于只是读取
          # xcconfig 设置并打印警告，不修改项目，因此不存在竞态条件。
          def warn_about_xcconfig_overrides
            targets = targets_to_integrate
            return if targets.empty?

            if targets.size <= 1
              warn_single_target(targets.first)
              return
            end

            pool_size = compute_pool_size
            Pod::UI.message "- Checking xcconfig overrides for #{targets.size} targets (pool: #{pool_size})"
            pool = Concurrent::FixedThreadPool.new(pool_size)
            targets.each do |aggregate_target|
              pool.post do
                warn_single_target(aggregate_target)
              rescue StandardError => e
                Pod::UI.warn "[cocoapods-podgenerate] Xcconfig warning error: #{e.message}"
              end
            end
            pool.shutdown
            unless pool.wait_for_termination(Pod::PodGenerate::Parallel::ThreadPool::DEFAULT_TIMEOUT)
              Pod::UI.warn '[cocoapods-podgenerate] UserIntegratorPatch: timed out waiting for xcconfig override checks'
            end
          rescue NameError
            targets.each { |t| warn_single_target(t) }
          end

          private

          # 对单个 AggregateTarget 检查其所有 user target 的 xcconfig 覆盖情况。
          #
          # 遍历逻辑：
          #   1. 遍历 aggregate_target 的所有 user_target
          #   2. 对每个 user_target 的每个构建配置，取出对应 xcconfig 中的设置
          #   3. 比较 xcconfig 设置与当前构建设置：如果用户已在构建设置中赋值
          #      （非 $(inherited)），则打印覆盖警告
          #
          # 忽略 CODE_SIGN_IDENTITY 等特定 key（定义在 IGNORED_KEYS 中），
          # 这些 key 的覆盖是预期行为，不需要警告。
          #
          # 在线程池的某个槽位中运行，通过 rescue 捕获异常避免单 target 错误
          # 影响其他 target 的检查。
          #
          # 注意：print_override_warning 是原始 UserProjectIntegrator 类的
          # private 方法。Ruby 允许从 prepended module 中以隐式 receiver 的
          # 方式调用 private 方法（无需显式 self. 前缀）。
          def warn_single_target(aggregate_target)
            aggregate_target.user_targets.each do |user_target|
              user_target.build_configurations.each do |config|
                xcconfig = aggregate_target.xcconfigs[config.name]
                next unless xcconfig

                (xcconfig.to_hash.keys - UserIntegratorPatch::IGNORED_KEYS).each do |key|
                  target_values = config.build_settings[key]
                  if target_values &&
                      !UserIntegratorPatch::INHERITED_FLAGS.any? { |flag| target_values.include?(flag) }
                    print_override_warning(aggregate_target, user_target, config, key)
                  end
                end
              end
            end
          end

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
