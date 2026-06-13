# frozen_string_literal: true

# [cocoapods-podgenerate]
# `pod podgenerate` CLI 命令 — 带优化运行 pod install 的快捷方式。
#
# 用法:
#   pod podgenerate              # 运行优化的 pod install
#   pod podgenerate --debug      # 启用详细性能分析输出
#   pod podgenerate --verbose    # 传递 --verbose 给 pod install
#
# v0.1.4 修复 (M7):
#   用户参数（如 --no-repo-update、--verbose）现在会正确传递给
#   底层的 pod install 命令，不再被静默丢弃。

module Pod
  class Command
    class Podgenerate < Command
      self.summary = 'Run pod install with PodGenerate optimizations'
      self.description = <<-DESC
        Speeds up pod install for large projects (200+ pods) by enabling
        parallel processing, optimized dependency analysis, and incremental
        project generation.
      DESC

      self.arguments = []

      def self.options
        [
          ['--debug', 'Enable verbose profiling output and detailed timing logs']
        ].concat(super)
      end

      def initialize(argv)
        @debug = argv.flag?('debug', false)
        # v0.1.4: 保存原始参数，稍后传递给 pod install（修复 M7）
        @remaining_argv = argv
        super
      end

      def run
        if @debug
          Pod::PodGenerate::Benchmark::Profiler.enable!
          Pod::UI.puts '[cocoapods-podgenerate] Debug mode enabled — verbose profiling output will be shown.'
        end

        Pod::PodGenerate.activate

        # 委托给标准的 pod install 命令执行
        # v0.1.4: 传递用户原参数给 pod install（修复 M7）
        install_command = Pod::Command::Install.new(CLAide::ARGV.new(@remaining_argv.remainder!))
        install_command.run
      end
    end
  end
end
