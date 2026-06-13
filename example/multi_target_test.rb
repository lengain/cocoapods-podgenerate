#!/usr/bin/env ruby
# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════
#  多 Target 场景模拟 & 第4步耗时对比测试
#
#  流程:
#   1. 读取 Example.xcodeproj，复制已有 target 创建 N 个额外 native target
#   2. 生成 Podfile: Example 用全部 150 pods, Target2~6 各用子集
#   3. 分别用/不用插件运行 pod install
#   4. 输出第4步耗时对比
# ═══════════════════════════════════════════════════════════

require 'fileutils'
require 'xcodeproj'

BASE_DIR = File.expand_path(File.dirname(__FILE__))
A_PROJ_DIR = File.join(BASE_DIR, 'ExampleA', 'Example.xcodeproj')
B_PROJ_DIR = File.join(BASE_DIR, 'ExampleB', 'Example.xcodeproj')
TARGET_COUNT = 6  # 1 original + 5 duplicates = 6 targets total

# ── Step 1: 复制 native target ───────────────────────────────
def add_extra_targets(proj_dir, count)
  project = Xcodeproj::Project.open(proj_dir)
  main_group = project.main_group

  # Find the original target (named "Example")
  original_target = project.targets.find { |t| t.name == 'Example' }
  unless original_target
    puts "  ⚠️  Original target 'Example' not found in #{proj_dir}"
    return false
  end

  added = 0
  (2..count).each do |i|
    target_name = "ExampleTarget#{i}"
    next if project.targets.any? { |t| t.name == target_name }

    # Clone the original target's build configurations
    new_target = project.new_target(
      original_target.symbol_type,
      target_name,
      original_target.platform_name,
      original_target.deployment_target,
      nil,
      original_target.product_type
    )

    # Copy build phases from original target
    original_target.build_phases.each do |phase|
      new_target.build_phases << phase.dup
    end

    # Copy build configurations
    original_target.build_configurations.each do |config|
      matching_config = new_target.build_configurations.find { |c| c.name == config.name }
      if matching_config
        matching_config.build_settings.merge!(config.build_settings)
      end
    end

    # Create a product reference
    product_ref = project.products_group.new_product_ref_for_target(target_name, original_target.product_type)
    new_target.product_reference = product_ref

    added += 1
  end

  project.save
  puts "  ✅ Added #{added} extra targets to #{File.basename(proj_dir)}"
  added > 0
end

# ── Step 2: 生成多 target Podfile ────────────────────────────
def generate_podfile(target_count, output_path, with_plugin: false)
  File.open(output_path, 'w') do |f|
    if with_plugin
      f.puts '# Load PodGenerate plugin'
      f.puts '$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))'
      f.puts 'require "cocoapods-podgenerate"'
      f.puts 'Pod::PodGenerate.activate'
      f.puts ''
    end

    f.puts "source 'https://cdn.cocoapods.org/'"
    f.puts ''
    f.puts "platform :ios, '15.0'"
    f.puts 'use_frameworks!'
    f.puts 'inhibit_all_warnings!'
    f.puts ''

    # Target 1: all 150 pods (300MB+, includes high/mid/base layers)
    f.puts "target 'Example' do"
    f.puts '  # Full dependency: all 150 pods'
    f.puts "  pod 'PodGen_1', :path => '../generated_pods/PodGen_1'"
    f.puts "  pod 'PodGen_2', :path => '../generated_pods/PodGen_2'"
    f.puts '  # ... all 150 pods referenced'
    (1..150).each do |i|
      f.puts "  pod 'PodGen_#{i}', :path => '../generated_pods/PodGen_#{i}'"
    end
    f.puts 'end'
    f.puts ''

    # Targets 2..N: subsets of pods
    (2..target_count).each do |i|
      target_name = "ExampleTarget#{i}"
      f.puts "target '#{target_name}' do"
      # Each additional target gets a different subset of pods
      # Roughly 20-30 pods each, distributed across layers
      base_start = ((i - 2) * 30) % 120 + 1
      base_end = [base_start + 29, 150].min
      (base_start..base_end).each do |j|
        f.puts "  pod 'PodGen_#{j}', :path => '../generated_pods/PodGen_#{j}'"
      end
      f.puts 'end'
      f.puts ''
    end
  end
  puts "  ✅ Generated Podfile with #{target_count} targets"
end

# ── Step 3: 运行测试并计时 ──────────────────────────────────
def measure_phase4(label, dir, cmd)
  puts "━━━ #{label}"

  # Clean pods
  FileUtils.rm_rf(File.join(dir, 'Pods'))
  FileUtils.rm_f(File.join(dir, 'Podfile.lock'))

  # Run and capture time output
  tmp_out = '/tmp/mt_out.txt'
  tmp_err = '/tmp/mt_err.txt'

  Dir.chdir(dir) do
    system "/usr/bin/time bash -c '#{cmd}' 2>#{tmp_err} >#{tmp_out}"
  end

  # Parse timing
  time_line = File.readlines(tmp_err).last
  real_val = time_line.to_s.split[0].to_f

  # Check for completion
  complete = File.read(tmp_out).include?('complete')

  if complete
    puts "     ✅ Pod installation complete"
  else
    puts "     ⚠️  May have errors"
    File.read(tmp_out).lines.last(3).each { |l| puts "     #{l.strip}" unless l.strip.empty? }
  end
  puts "     ⏱  real: #{real_val}s"
  puts ""

  real_val
end

# ── Main ──────────────────────────────────────────────────────
puts ""
puts "╔══════════════════════════════════════════════════════════════╗"
puts "║  多 Target 场景 — 第4步 Integrating client project 测试    ║"
puts "║  #{TARGET_COUNT} targets · 150 pods                        ║"
puts "╚══════════════════════════════════════════════════════════════╝"
puts ""

# 1. Add extra targets to both ExampleA and ExampleB projects
puts "━━━ 向 Xcode 工程添加额外 native targets..."
add_extra_targets(A_PROJ_DIR, TARGET_COUNT)
add_extra_targets(B_PROJ_DIR, TARGET_COUNT)
puts ""

# 2. Generate multi-target Podfiles
puts "━━━ 生成多 target Podfiles..."
generate_podfile(TARGET_COUNT, File.join(BASE_DIR, 'ExampleA', 'Podfile'), with_plugin: true)
generate_podfile(TARGET_COUNT, File.join(BASE_DIR, 'ExampleB', 'Podfile'), with_plugin: false)
puts ""

# 3. Run tests
puts "=" * 60
time_a = measure_phase4("[A] ExampleA (带插件) — #{TARGET_COUNT} targets", File.join(BASE_DIR, 'ExampleA'), 'ruby run_with_plugin.rb')
time_b = measure_phase4("[B] ExampleB (无插件) — #{TARGET_COUNT} targets", File.join(BASE_DIR, 'ExampleB'), 'pod install')

# 4. Output comparison
saved = time_b - time_a
pct = time_b > 0 ? (saved / time_b * 100).round(1) : 0

puts ""
puts "╔══════════════════════════════════════════════════════════════╗"
puts "║  多 Target 测试结果对比                                     ║"
puts "╚══════════════════════════════════════════════════════════════╝"
puts ""
printf "┌──────────────────────┬──────────┬──────────┐\n"
printf "│ %-20s │ %-8s │ %-8s │\n", "场景", "耗时(real)", "提升"
printf "├──────────────────────┼──────────┼──────────┤\n"
printf "│ %-20s │ %8.2fs │ %+7.1f%% │\n", "带插件 (ExampleA)", time_a, pct
printf "│ %-20s │ %8.2fs │          │\n", "无插件 (ExampleB)", time_b
printf "├──────────────────────┼──────────┼──────────┤\n"
printf "│ %-20s │ %8.2fs │          │\n", "插件节省", saved
printf "└──────────────────────┴──────────┴──────────┘\n"
puts ""
puts "说明: 测试用时包含完整 pod install 5步（含第4步内多个 target 集成）"
puts ""
