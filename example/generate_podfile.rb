#!/usr/bin/env ruby
# frozen_string_literal: true

#
# generate_podfile.rb
# ═══════════════════════════════════════════════════════════
#  CocoaPods 性能测试 — 三层级依赖拓扑生成器
# ═══════════════════════════════════════════════════════════
#
#  生成 150 个 pod，三层级密集依赖拓扑（目标 1200+ 依赖边）：
#
#  层级                  数量  PodGen_ID 范围  依赖数     模拟场景
#  ─────────────────────────────────────────────────────────────────
#  Base（底层库）          35   1–35        0        基础工具库 (JSON/Log/Network/…)
#  Mid（中层库）           50   36–85       7–9      功能组件 (LBS/Auth/Player/…)
#  High（高层库）          65   86–150     16–18     业务模块 (Feed/Checkout/Moments/…)
#
#  依赖原则：
#    • Base → 无依赖
#    • Mid  → 仅依赖 Base (1-35)
#    • High → 依赖 Mid (36-85) + Base (1-35)，不跨层引用同层
#    • 生成拓扑整体为 DAG，CocoaPods 依赖解析器可正常处理
#
#  依赖分布特点（模拟真实场景）：
#    • 某些基础库被大量引用（"核心依赖"，如 PodGen_1 被 ~60+ 个上级引用）
#    • 某些基础库较少被引用（"专项库"，如 PodGen_35 被 ~10 个引用）
#    • 中高层依赖呈现「小世界」特性：相邻编号的 pod 倾向于引用类似的底层集合
#

require 'fileutils'

BASE_DIR = File.expand_path(File.dirname(__FILE__))
TEMPLATES_DIR = File.join(BASE_DIR, 'pod_templates')
GENERATED_PODS_DIR = File.join(BASE_DIR, 'generated_pods')
PODFILE_PATH = File.join(BASE_DIR, 'Podfile')

# ── 层级配置 ──────────────────────────────────────────────

BASE_COUNT  = 35   # 1..35
MID_COUNT   = 50   # 36..85
HIGH_COUNT  = 65   # 86..150
TOTAL_PODS  = BASE_COUNT + MID_COUNT + HIGH_COUNT  # 150

# ── 日志 ──────────────────────────────────────────────────

def log(msg)
  puts "  #{msg}"
end

# ── 依赖计算 ──────────────────────────────────────────────
#
#  所有依赖计算使用 确定性算法（无随机），保证每次生成结果一致。
#

# 从 base 池 (1..BASE_COUNT) 中为第 i 个 mid pod 选取 count 个依赖
# popularity_offset 控制"核心依赖"的偏移，使某些 base 被更频繁引用
def pick_base_deps(mid_index, count, popularity_offset = 0)
  # mid_index 为 0-based (0..49)
  # 使用质数乘法器产生均匀分布但确定性的选择
  deps = Set.new
  count.times do |j|
    raw = (mid_index * 23 + j * 17 + popularity_offset) % BASE_COUNT + 1
    deps.add(raw)
  end
  # 保证正好 count 个（处理可能的重复）
  attempt = 0
  while deps.size < count
    extra = (mid_index * 11 + attempt * 31 + popularity_offset) % BASE_COUNT + 1
    deps.add(extra)
    attempt += 1
  end
  deps.to_a.sort
end

# 为第 i 个 high pod (0-based, 0..64) 选取依赖
# 返回 [ [mid_deps], [base_deps] ]
def pick_high_deps(high_index)
  seed = high_index * 31 + 13

  # 选取 9~10 个 mid pod (BASE_COUNT+1 .. BASE_COUNT+MID_COUNT)
  mid_lo = BASE_COUNT + 1         # 36
  mid_hi = BASE_COUNT + MID_COUNT  # 85
  mid_count = 9 + (high_index % 2)  # 9 or 10
  mid_deps = Set.new
  mid_count.times do |j|
    raw = mid_lo + ((seed + j * 17) % MID_COUNT)
    mid_deps.add(raw)
  end
  while mid_deps.size < mid_count
    extra = mid_lo + ((seed + mid_deps.size * 23) % MID_COUNT)
    mid_deps.add(extra)
  end

  # 选取 7~8 个 base pod (1..BASE_COUNT)
  base_count = 17 - mid_count  # 8 if mid=9, 7 if mid=10
  base_deps = Set.new
  base_count.times do |j|
    raw = ((seed + j * 13 + 7) % BASE_COUNT) + 1
    base_deps.add(raw)
  end
  while base_deps.size < base_count
    extra = ((seed + base_deps.size * 29) % BASE_COUNT) + 1
    base_deps.add(extra)
  end

  [mid_deps.to_a.sort, base_deps.to_a.sort]
end

# 统计每个 base pod 被引用的次数（用于验证分布合理性）
def compute_popularity_stats(mid_dep_sets, high_mid_deps, high_base_deps)
  counts = Hash.new(0)
  # mid 引用 base
  mid_dep_sets.each do |deps|
    deps.each { |d| counts[d] += 1 }
  end
  # high 引用 mid
  high_mid_deps.each do |deps|
    deps.each { |d| counts[d] += 1 }
  end
  # high 引用 base
  high_base_deps.each do |deps|
    deps.each { |d| counts[d] += 1 }
  end
  counts
end

# ── 预计算依赖 ────────────────────────────────────────────

log "计算 #{TOTAL_PODS} 个 pod 的依赖拓扑..."

# base pods (1..35): 无依赖
# mid pods (36..85): 7~9 个 base 依赖
mid_dep_sets = []
MID_COUNT.times do |i|
  count = case i % 5
          when 0, 3 then 7
          when 1, 4 then 8
          else 9
          end
  # popularity_offset 让不同 mid 对 base 的引用模式不同
  offset = (i / 3) * 5
  deps = pick_base_deps(i, count, offset)
  mid_dep_sets << deps
end

# high pods (86..150): 16~18 个依赖 (mid + base)
high_mid_deps = []
high_base_deps = []
HIGH_COUNT.times do |i|
  md, bd = pick_high_deps(i)
  high_mid_deps << md
  high_base_deps << bd
end

# 打印依赖统计
popularity = compute_popularity_stats(mid_dep_sets, high_mid_deps, high_base_deps)
pop_sorted = popularity.sort_by { |_, v| -v }
most_popular = pop_sorted.first(5).map { |k, v| "PodGen_#{k}(#{v}次)" }.join(', ')
least_popular = pop_sorted.last(5).map { |k, v| "PodGen_#{k}(#{v}次)" }.join(', ')
log "热门底层库（被引用最多）: #{most_popular}"
log "冷门底层库（被引用最少）: #{least_popular}"

total_dep_edges = mid_dep_sets.flatten.size + high_mid_deps.flatten.size + high_base_deps.flatten.size
log "总依赖边数: #{total_dep_edges}"

# ── 清理并重建设备 ───────────────────────────────────────

log "清理 generated_pods/ ..."
FileUtils.rm_rf(GENERATED_PODS_DIR)
FileUtils.mkdir_p(GENERATED_PODS_DIR)

# ── 模板映射 ─────────────────────────────────────────────
#
#  为每个 pod 分配一个模板（用于复制 Classes 和 Assets）
#  base 层用较轻的模板，mid 和 high 用更丰富的模板
#
def template_for_pod(pod_index, total_templates = 20)
  # 通过不同的偏移让三层的模板分布不同
  offset = if pod_index <= BASE_COUNT
             pod_index - 1  # base: 1..35 → template 1..20 循环
           elsif pod_index <= BASE_COUNT + MID_COUNT
             (pod_index - BASE_COUNT - 1) * 3  # mid: 不同节奏
           else
             (pod_index - BASE_COUNT - MID_COUNT - 1) * 5 + 7  # high: 更分散
           end
  ((offset % total_templates) + 1).to_s.rjust(2, '0')
end

# ── Podspec 生成 ──────────────────────────────────────────

#  layer_label 用于 podspec summary
def layer_label(index)
  if index <= BASE_COUNT
    "BaseUtility"
  elsif index <= BASE_COUNT + MID_COUNT
    "MidComponent"
  else
    "HighBusiness"
  end
end

#  layer_description
def layer_description(index)
  if index <= BASE_COUNT
    "底层基础工具库，提供核心基础设施能力"
  elsif index <= BASE_COUNT + MID_COUNT
    "中层功能组件，组合底层库实现特定业务能力"
  else
    "高层业务模块，编排多个中层组件实现完整业务场景"
  end
end

def generate_podspec(pod_index, deps)
  name = "PodGen_#{pod_index}"
  layer = layer_label(pod_index)
  desc = layer_description(pod_index)
  dep_lines = deps.map { |d| "  s.dependency 'PodGen_#{d}', '~> 1.0'" }.join("\n")

  <<~SPEC
    Pod::Spec.new do |s|
      s.name             = '#{name}'
      s.version          = '1.0.0'
      s.summary          = '#{name} - [#{layer}] #{desc}'
      s.description      = <<-DESC
          #{name} is a auto-generated test pod for CocoaPods performance benchmarking.
          Layer: #{layer}. #{desc}
      DESC
      s.homepage         = 'https://github.com/example/#{name}'
      s.license          = { :type => 'MIT', :file => 'LICENSE' }
      s.author           = { 'Example' => 'example@example.com' }
      s.source           = { :git => 'https://github.com/example/#{name}.git', :tag => s.version.to_s }
      s.ios.deployment_target = '15.0'
      s.swift_version    = '5.0'

      s.source_files     = 'Classes/**/*.{h,m,swift}'
      s.public_header_files = 'Classes/**/*.h'
      s.resource_bundles = {
        '#{name}Resources' => ['Assets/**/*', 'Resources/**/*']
      }

      s.frameworks       = 'Foundation', 'UIKit'
      s.requires_arc     = true
  #{dep_lines}
    end
  SPEC
end

# ── 执行生成 ──────────────────────────────────────────────

log "生成 #{TOTAL_PODS} 个 pod..."
(1..TOTAL_PODS).each do |pod_index|
  name = "PodGen_#{pod_index}"

  # 确定依赖
  deps = if pod_index <= BASE_COUNT
           []  # base: 无依赖
         elsif pod_index <= BASE_COUNT + MID_COUNT
           mid_dep_sets[pod_index - BASE_COUNT - 1]  # mid: 2~3 base deps
         else
           high_mid_deps[pod_index - BASE_COUNT - MID_COUNT - 1] +
             high_base_deps[pod_index - BASE_COUNT - MID_COUNT - 1]  # high: 8~10 deps
         end

  # 选择模板
  tmpl_num = template_for_pod(pod_index)
  tmpl_name = "PodBase#{tmpl_num}"
  tmpl_dir = File.join(TEMPLATES_DIR, tmpl_name)

  # 创建 pod 目录
  pod_dir = File.join(GENERATED_PODS_DIR, name)
  FileUtils.mkdir_p(pod_dir)

  # 写入 podspec
  podspec = generate_podspec(pod_index, deps)
  File.write(File.join(pod_dir, "#{name}.podspec"), podspec)

  # 复制 template 的 Classes / Assets / Resources / LICENSE
  %w[Classes Assets Resources LICENSE].each do |sub|
    src = File.join(tmpl_dir, sub)
    if File.exist?(src)
      FileUtils.cp_r(src, pod_dir)
    end
  end
end

# ── 生成 Podfile ──────────────────────────────────────────

log "生成 Podfile ..."

File.open(PODFILE_PATH, 'w') do |f|
  f.puts <<~HEADER
    # frozen_string_literal: true

    #
    # ════════════════════════════════════════════════════════
    #  WARNING: Auto-generated for CocoaPods performance testing.
    #  三层级依赖拓扑测试（#{TOTAL_PODS} pods, #{total_dep_edges} edges）
    #  Generated at: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
    # ════════════════════════════════════════════════════════
    #

    source 'https://cdn.cocoapods.org/'

    platform :ios, '15.0'
    use_frameworks!
    inhibit_all_warnings!

  HEADER

  f.puts "target 'Example' do"
  f.puts "  # ── 全部 #{TOTAL_PODS} 个测试 pod ──"
  f.puts ""

  # base 段: 1..BASE_COUNT
  f.puts "  # ═══ Base Layer (底层库, #{BASE_COUNT}个, 无依赖) ═══"
  (1..BASE_COUNT).each do |i|
    f.puts "  pod 'PodGen_#{i}', :path => 'generated_pods/PodGen_#{i}'"
  end
  f.puts ""

  # mid 段: BASE_COUNT+1 .. BASE_COUNT+MID_COUNT
  f.puts "  # ═══ Mid Layer (中层库, #{MID_COUNT}个, 7-9个依赖) ═══"
  (BASE_COUNT + 1..BASE_COUNT + MID_COUNT).each do |i|
    f.puts "  pod 'PodGen_#{i}', :path => 'generated_pods/PodGen_#{i}'"
  end
  f.puts ""

  # high 段: BASE_COUNT+MID_COUNT+1 .. TOTAL_PODS
  f.puts "  # ═══ High Layer (高层库, #{HIGH_COUNT}个, 16-18个依赖) ═══"
  (BASE_COUNT + MID_COUNT + 1..TOTAL_PODS).each do |i|
    f.puts "  pod 'PodGen_#{i}', :path => 'generated_pods/PodGen_#{i}'"
  end

  f.puts ""
  f.puts "end"

  f.puts <<~POST

    post_install do |installer|
      installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
          config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
          config.build_settings['SWIFT_VERSION'] = '5.0'
        end
      end
    end
  POST
end

# ── 验证 ──────────────────────────────────────────────────

puts ""
log "═" * 50
log "生成完成，验证中..."

podfile_lines = File.readlines(PODFILE_PATH)
pod_count = podfile_lines.count { |line| line.match?(/^\s*pod\s+'PodGen_\d+'/) }
gen_pod_dirs = Dir.glob(File.join(GENERATED_PODS_DIR, '*')).count { |f| File.directory?(f) }
gen_podspecs = Dir.glob(File.join(GENERATED_PODS_DIR, '*', '*.podspec')).count

log "  Podfile entries: #{pod_count}/#{TOTAL_PODS}"
log "  Generated dirs:  #{gen_pod_dirs}/#{TOTAL_PODS}"
log "  Generated specs: #{gen_podspecs}/#{TOTAL_PODS}"

if pod_count == TOTAL_PODS && gen_pod_dirs == TOTAL_PODS && gen_podspecs == TOTAL_PODS
  log "✓ 生成验证通过"
else
  log "✗ 生成验证失败 - 请检查"
end

log ""
log "═" * 50
log "拓扑统计："
log "  Base(1-#{BASE_COUNT}):  0 个依赖"
log "  Mid(#{BASE_COUNT + 1}-#{BASE_COUNT + MID_COUNT}):  #{mid_dep_sets.map(&:size).sum} 条边 (每库 #{mid_dep_sets.map(&:size).min}~#{mid_dep_sets.map(&:size).max} 个依赖)"
log "  High(#{BASE_COUNT + MID_COUNT + 1}-#{TOTAL_PODS}): #{total_dep_edges - mid_dep_sets.flatten.size} 条边 (每库 #{(high_mid_deps + high_base_deps).map(&:size).min}~#{(high_mid_deps + high_base_deps).map(&:size).max} 个依赖)"
log "  总依赖边数: #{total_dep_edges}"
log "  总计 pods:  #{TOTAL_PODS}"
log "═" * 50
