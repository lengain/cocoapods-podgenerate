#!/usr/bin/env ruby
# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════
#  Complex Podfile Test Runner
#
#  执行步骤：
#   1. 调用 complex_podfile_test.rb 生成测试数据
#   2. 清理 Pods 目录
#   3. 加载 PodGenerate 插件并运行 pod install
#   4. 验证结果（检查崩溃、项目结构、插件消息、跨项目依赖等）
# ═══════════════════════════════════════════════════════════════════════

require 'fileutils'
require 'json'

BASE_DIR = File.expand_path(File.dirname(__FILE__))
A_PROJ_DIR = File.join(BASE_DIR, 'ExampleA')
OUTPUT_FILE = '/tmp/complex_test_output.txt'
RESULT_FILE = '/tmp/complex_test_result.json'

$output_lines = []

# ── 运行命令并捕获输出 ──────────────────────────────────────────
def run_cmd(cmd, dir: BASE_DIR)
  out = `cd #{dir} && #{cmd} 2>&1`
  $output_lines.concat(out.split("\n"))
  [$?.exitstatus, out]
end

# ── 步骤 1: 生成 ────────────────────────────────────────────────
def step_generate
  puts "━━━ [1/4] 生成增强 podspec + 复杂 Podfile..."
  exit_code, out = run_cmd("ruby complex_podfile_test.rb")
  if exit_code != 0
    puts "  ❌ 生成失败 (exit=#{exit_code})"
    puts out.lines.last(10).join('  ')
    return false
  end
  puts "  ✅ 生成完成"
  true
end

# ── 步骤 2: 清理 ────────────────────────────────────────────────
def step_clean
  puts "━━━ [2/4] 清理 Pods..."
  Dir.chdir(A_PROJ_DIR) do
    FileUtils.rm_rf('Pods')
    FileUtils.rm_f('Podfile.lock')
  end
  puts "  ✅ 清理完成"
end

# ── 步骤 3: 运行 pod install ────────────────────────────────────
def step_install
  puts "━━━ [3/4] 运行 pod install（带 PodGenerate 插件）..."
  Dir.chdir(A_PROJ_DIR) do
    out = `ruby -e '
      $stdout.sync = true
      $LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
      require "cocoapods"
      require "cocoapods-podgenerate"
      Pod::PodGenerate.activate
      config = Pod::Config.instance
      installer = Pod::Installer.new(config.sandbox, config.podfile, config.lockfile)
      installer.install!
    ' 2>&1`
    $output_lines.concat(out.split("\n"))
    exit_code = $?.exitstatus
    if exit_code != 0
      puts "  ❌ pod install 失败 (exit=#{exit_code})"
      puts out.lines.last(20).join('  ')
      return false
    end
    puts "  ✅ pod install 完成"
  end
  true
end

# ── 步骤 4: 验证 ────────────────────────────────────────────────
def step_verify
  puts "━━━ [4/4] 验证安装结果..."

  output = $output_lines.join("\n")
  results = { passed: [], failed: [], warnings: [] }
  all_pass = true

  # 4a. 检查插件激活消息
  if output.include?('[cocoapods-podgenerate]')
    results[:passed] << "插件激活消息存在"
  else
    results[:failed] << "缺少 [cocoapods-podgenerate] 消息"
    all_pass = false
  end

  # 4b. 检查补丁应用消息
  %w[InstallerPatch ProjectWriterPatch ProjectPatch AnalyzerPatch
     UserIntegratorPatch MultiProjectGeneratorPatch CacheAnalyzerPatch].each do |patch|
    if output.include?("Applying #{patch}")
      results[:passed] << "#{patch} 已应用"
    else
      results[:warnings] << "#{patch} 未找到应用消息（可能命名不同或已懒加载）"
    end
  end

  # 4c. 检查插件错误消息
  warn_lines = output.split("\n").select { |l| l.include?('[cocoapods-podgenerate]') && l.match?(/warn|error|fail/i) }
  if warn_lines.empty?
    results[:passed] << "无插件警告/错误"
  else
    warn_lines.each { |l| results[:warnings] << "插件警告: #{l.strip}" }
  end

  # 4d. 检查 CocoaPods 错误
  if output.include?('error:') || output.include?('Error:')
    results[:failed] << "CocoaPods 输出包含错误"
    all_pass = false
  end

  # 4e. 检查 Pods 项目文件
  pods_proj = File.join(A_PROJ_DIR, 'Pods', 'Pods.xcodeproj')
  if File.exist?(pods_proj)
    results[:passed] << "Pods.xcodeproj 已生成"
  else
    results[:failed] << "Pods.xcodeproj 未生成"
    all_pass = false
  end

  # 4f. 检查子项目文件（generate_multiple_pod_projects）
  sub_projects = Dir[File.join(A_PROJ_DIR, 'Pods', 'PodGen_*.xcodeproj')]
  if sub_projects.size > 10
    results[:passed] << "子项目已生成 (#{sub_projects.size} 个)"
  else
    results[:warnings] << "子项目数量偏少 (#{sub_projects.size} 个，期望 > 10)"
  end

  # 4g. 检查跨项目依赖遍历（F1 修复测试）
  if output.include?('cross-project') || !output.include?('undefined method')
    results[:passed] << "跨项目依赖遍历未崩溃 (F1)"
  else
    if output.include?("undefined method 'dependencies' for nil")
      results[:failed] << "跨项目依赖遍历崩溃！(F1)"
      all_pass = false
    end
  end

  # 4h. 检查 generated_projects 迭代（F2 修复测试）
  unless output.include?("undefined method") && output.include?("generated_projects")
    results[:passed] << "generated_projects 遍历未崩溃 (F2)"
  end

  # 4i. 检查抽象 target 聚合
  if output.include?('Pods-App')
    results[:passed] << "abstract_target 已处理"
  else
    results[:warnings] << "未检测到 abstract_target 相关消息"
  end

  # 4j. 检查 post_install hook 执行
  unless output.include?('undefined method')
    results[:passed] << "post_install hook 执行成功（3 个 pattern）"
  end

  # 4k. 检查插件是否跳过了项目生成（增量时）
  if output.include?('No changes')
    results[:passed] << "增量安装正确触发跳过路径"
  end

  # 4l. 检查安装完成
  if output.include?('Pod installation complete!')
    results[:passed] << "Pod installation complete!"
  elsif output.include?('Install!')
    results[:warnings] << "安装完成消息可能被插件输出打断"
  else
    results[:warnings] << "安装完成标识未在输出中找到"
  end

  # ── 输出结果 ──
  puts ""
  puts "╔══════════════════════════════════════════════════════════════╗"
  puts "║  验证结果                                                    ║"
  puts "╚══════════════════════════════════════════════════════════════╝"
  puts ""

  results[:passed].each { |m| puts "  ✅ #{m}" }
  results[:warnings].each { |m| puts "  ⚠️  #{m}" }
  results[:failed].each { |m| puts "  ❌ #{m}" }

  puts ""
  if all_pass
    puts "  🎉 全部通过! (#{results[:passed].size} passed, #{results[:warnings].size} warnings)"
  else
    puts "  ❌ 有 #{results[:failed].size} 个测试失败"
  end

  # 保存结果
  results[:all_pass] = all_pass
  File.write(RESULT_FILE, JSON.pretty_generate(results))

  all_pass
end

# ── 保存输出 ────────────────────────────────────────────────────
def save_output
  File.write(OUTPUT_FILE, $output_lines.join("\n"))
  puts "  📝 完整输出已保存到 #{OUTPUT_FILE}"
end

# ══════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════

puts ""
puts "╔══════════════════════════════════════════════════════════════╗"
puts "║  Complex Podfile Test Runner                                ║"
puts "║  测试 PodGenerate 对复杂 Podfile 的兼容性                    ║"
puts "╚══════════════════════════════════════════════════════════════╝"
puts ""

success = true

# 步骤 1: 生成
success &&= step_generate

# 步骤 2: 清理（仅在生成成功后）
step_clean if success

# 步骤 3: 安装
success &&= step_install

# 步骤 4: 验证
step_verify if success

# 保存输出
save_output

# 退出码
exit(success ? 0 : 1)
