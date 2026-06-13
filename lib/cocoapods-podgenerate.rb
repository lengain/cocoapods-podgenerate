# frozen_string_literal: true

# [cocoapods-podgenerate]
# 插件入口文件 — 加载所有补丁和工具模块，激活优化。
#
# 加载顺序（重要—有依赖关系）:
#   1. 各 patch 文件（通过 prepend monkey-patch CocoaPods 内部类）
#   2. 并行工具模块（线程池、批处理器）
#   3. 性能分析器
#
# 激活方式:
#   - `plugin 'cocoapods-podgenerate'` in Podfile → CocoaPods 加载 cocoapods_plugin.rb
#     → require 此文件 → 如果 Pod::HooksManager 已定义则立即 activate
#   - 如果 Pod::HooksManager 尚未定义（例如加载顺序不同），
#     使用 TracePoint 延迟激活（带 500 次安全检查防止资源泄漏）
#   - hooks.rb 注册了 :pre_install hook 作为兜底（如果 TracePoint 也错过了）

require 'cocoapods-podgenerate/patches/installer_patch'
require 'cocoapods-podgenerate/patches/project_patch'
require 'cocoapods-podgenerate/patches/project_writer_patch'
require 'cocoapods-podgenerate/patches/analyzer_patch'
require 'cocoapods-podgenerate/patches/user_integrator_patch'
require 'cocoapods-podgenerate/patches/multi_project_generator_patch'
require 'cocoapods-podgenerate/patches/cache_analyzer_patch'
require 'cocoapods-podgenerate/parallel/thread_pool'
require 'cocoapods-podgenerate/parallel/batch_processor'
require 'cocoapods-podgenerate/benchmark/profiler'

module Pod
  module PodGenerate
    # 激活所有优化补丁
    #
    # 幂等安全：多次调用只执行一次（@activated 守卫）。
    # 所有补丁通过 Module#prepend 注入，如果重复 prepend 会导致
    # 祖先链中出现重复模块，super 调用链混乱。
    def self.activate
      return if @activated
      @activated = true

      # 确保 hooks 被加载（pre_install hook 作为兜底激活路径）
      require_relative 'cocoapods-podgenerate/hooks'

      # 按依赖顺序注册补丁
      Pod::PodGenerate::Patches::InstallerPatch.apply
      Pod::PodGenerate::Patches::ProjectPatch.apply
      Pod::PodGenerate::Patches::ProjectWriterPatch.apply
      Pod::PodGenerate::Patches::AnalyzerPatch.apply
      Pod::PodGenerate::Patches::UserIntegratorPatch.apply
      Pod::PodGenerate::Patches::MultiProjectGeneratorPatch.apply
      Pod::PodGenerate::Patches::CacheAnalyzerPatch.apply

      # 安装性能分析器钩子
      Pod::PodGenerate::Benchmark::Profiler.install

      Pod::UI.message '[cocoapods-podgenerate] Activated!'
    end
  end
end

# 自动激活机制
#
# CocoaPods 的插件加载流程:
#   1. Podfile 中 `plugin 'cocoapods-podgenerate'` → CLAide 加载 cocoapods_plugin.rb
#   2. cocoapods_plugin.rb → require 'cocoapods-podgenerate' → 此文件
#   3. 此时 Pod::HooksManager 通常已由 cocoapods gem 的初始化过程定义
#
# 如果 Pod::HooksManager 已定义 → 立即激活
# 否则 → TracePoint 延迟激活，监听 :class 事件直到 HooksManager 被定义
if defined?(Pod::HooksManager)
  Pod::PodGenerate.activate
else
  # TracePoint 延迟激活（带安全检查）
  # [:class] 事件在 Ruby 每次打开 class/module 时触发
  # 500 次上限：正常情况下 HooksManager 在前 10-20 次就会被发现，
  # 如果超过 500 次说明加载环境异常，及时禁用避免永久性能开销
  count = 0
  tp = TracePoint.trace(:class) do |tp_event|
    count += 1
    if tp_event.self == Pod::HooksManager
      Pod::PodGenerate.activate
      tp_event.disable
    elsif count > 500
      tp_event.disable # 安全阀：防止资源泄漏
    end
  end
end
