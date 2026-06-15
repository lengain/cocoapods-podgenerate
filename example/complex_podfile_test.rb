#!/usr/bin/env ruby
# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════
#  Complex Podfile Test Generator
#
#  生成包含以下复杂特性的测试环境：
#    - abstract_target + inherit! :search_paths
#    - use_frameworks! :linkage => :static
#    - use_modular_headers!
#    - :configurations => ['Debug'] 按配置选择 pod
#    - test_spec / vendored_frameworks / script_phases / subspec
#    - 复杂 post_install hook（遍历 pods_project + generated_projects）
#    - 跨项目 target 依赖遍历（Flutter 风格，测试 F1 修复）
# ═══════════════════════════════════════════════════════════════════════

require 'fileutils'
require 'xcodeproj'
require 'set'

BASE_DIR = File.expand_path(File.dirname(__FILE__))
PODS_DIR = File.join(BASE_DIR, 'generated_pods')
A_PROJ_DIR = File.join(BASE_DIR, 'ExampleA', 'Example.xcodeproj')

# ── 需要增强的 pod 及其特性 ───────────────────────────────────────
ENHANCEMENTS = {
  # test_spec: 加测试 target (CocoaPods >= 1.3)
  1  => :test_spec,
  2  => :test_spec,
  3  => :test_spec,
  # vendored_frameworks: 内嵌 .framework
  4  => :vendored_framework,
  5  => :vendored_framework,
  # script_phases: pod 构建阶段
  6  => :script_phases,
  # vendored_libraries: 内嵌 .a
  7  => :vendored_libraries,
  # 更多 resource_bundles
  8  => :extra_resources,
  9  => :extra_resources,
  10 => :extra_resources,
  # subspec: 多 subspec
  11 => :subspec,
  # module_map: 显式 module map
  12 => :module_map,
  # static_framework: 强制静态 framework
  13 => :static_framework,
  14 => :static_framework,
  15 => :static_framework,
}.freeze

# ── 跳过路径标志（性能测试使用） ────────────────────────────────
$skip_enhanced = {}  # pod_index => boolean

# ══════════════════════════════════════════════════════════════════
#  1a. 增强 podspec
# ══════════════════════════════════════════════════════════════════

def enhance_podspecs!
  ENHANCEMENTS.each do |idx, type|
    pod_dir = File.join(PODS_DIR, "PodGen_#{idx}")
    podspec = File.join(pod_dir, "PodGen_#{idx}.podspec")
    next unless File.exist?(podspec)

    content = File.read(podspec)
    enhanced = send("enhance_#{type}", content, idx, pod_dir)
    if enhanced != content
      File.write(podspec, enhanced)
      puts "  ✅ Enhanced PodGen_#{idx} with #{type}"
    else
      puts "  ➖ PodGen_#{idx} already enhanced (#{type})"
    end
  end
end

# test_spec
def enhance_test_spec(content, idx, pod_dir)
  tests_dir = File.join(pod_dir, 'Tests')
  test_file = File.join(tests_dir, "PodGen_#{idx}Tests.m")
  return content if content.include?('test_spec') && File.exist?(test_file)
  FileUtils.mkdir_p(tests_dir)
  File.write(File.join(tests_dir, "PodGen_#{idx}Tests.m"),
    "#import <XCTest/XCTest.h>\n@interface PodGen_#{idx}Tests : XCTestCase\n@end\n" \
    "@implementation PodGen_#{idx}Tests\n- (void)testExample { XCTAssertTrue(YES); }\n@end\n")

  # 在 source_files 后插入 test_spec
  insert_before_end(content, <<-RUBY

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*.{h,m,swift}'
    test_spec.requires_app_host = true
  end
  RUBY
  )
end

# vendored_frameworks
def enhance_vendored_framework(content, idx, pod_dir)
  fw_name = "PodGen_#{idx}Framework.framework"
  fw_dir = File.join(pod_dir, 'VendoredFrameworks', fw_name)
  return content if content.include?('vendored_frameworks') && File.exist?(fw_dir)
  FileUtils.mkdir_p(fw_dir)
  # 创建 Info.plist
  File.write(File.join(fw_dir, 'Info.plist'),
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC " \
    "\"-//Apple//DTD PLIST 1.0//EN\" " \
    "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n" \
    "<dict><key>CFBundlePackageType</key><string>FMWK</string></dict>\n</plist>\n")
  # 创建占位二进制（空文件即可）
  File.write(File.join(fw_dir, fw_name), '')

  clobber_before_end(content, <<-RUBY

    s.vendored_frameworks = 'VendoredFrameworks/*.framework'
  RUBY
  )
end

# script_phases
def enhance_script_phases(content, idx, _pod_dir)
  return content if content.include?('script_phases')

  clobber_before_end(content, <<-RUBY

  s.script_phases = [
    { :name => 'Generate Build Info',
      :script => 'echo "PodGen_#{idx} built at $(date)" > "${CODESIGNING_FOLDER_PATH}/build_info.txt"',
      :execution_position => :before_compile }
  ]
  RUBY
  )
end

# vendored_libraries
def enhance_vendored_libraries(content, idx, pod_dir)
  return content if content.include?('vendored_libraries') && File.exist?(File.join(pod_dir, 'VendoredLibraries'))

  lib_dir = File.join(pod_dir, 'VendoredLibraries')
  FileUtils.mkdir_p(lib_dir)
  # 创建占位 .a
  File.write(File.join(lib_dir, "libDummy_#{idx}.a"), '')

  clobber_before_end(content, <<-RUBY

  s.vendored_libraries = 'VendoredLibraries/*.a'
  RUBY
  )
end

# extra_resources
def enhance_extra_resources(content, idx, pod_dir)
  return content if content.include?('ExtraResources') && File.exist?(File.join(pod_dir, 'ExtraAssets'))

  extra_dir = File.join(pod_dir, 'ExtraAssets')
  FileUtils.mkdir_p(extra_dir)
  File.write(File.join(extra_dir, "config_#{idx}.json"),
    "{\"pod\": \"PodGen_#{idx}\", \"extra\": true}\n")

  # 追加到 resource_bundles
  content = clobber_before_end(content, <<-RUBY

  s.resource_bundles = s.resource_bundles.merge({
    'PodGen_#{idx}Extra' => ['ExtraAssets/**/*']
  }) if s.respond_to?(:resource_bundles)
  RUBY
  )
end

# subspec
def enhance_subspec(content, idx, pod_dir)
  return content if content.include?('subspec')

  # 创建 UI 目录
  ui_dir = File.join(pod_dir, 'UI')
  FileUtils.mkdir_p(ui_dir)
  File.write(File.join(ui_dir, "PodGen_#{idx}Button.swift"),
    "import UIKit\n@objc public class PodGen_#{idx}Button: UIButton {\n" \
    "  public override init(frame: CGRect) { super.init(frame: frame); setup() }\n" \
    "  required init?(coder: NSCoder) { super.init(coder: coder); setup() }\n" \
    "  private func setup() { backgroundColor = .red }\n}\n")

  clobber_before_end(content, <<-RUBY

  s.default_subspec = 'Core'
  s.subspec 'Core' do |core|
    core.source_files = 'Classes/**/*.{h,m,swift}'
  end
  s.subspec 'UI' do |ui|
    ui.source_files = 'UI/**/*.{h,m,swift}'
    ui.dependency "\#{s.name}/Core"
  end
  RUBY
  )
end

# module_map
def enhance_module_map(content, idx, pod_dir)
  mm_path = File.join(pod_dir, "PodGen_#{idx}.modulemap")
  return content if content.include?('module_map') && File.exist?(mm_path)

  File.write(mm_path, "framework module PodGen_#{idx} {\n  umbrella header \"PodGen_#{idx}.h\"\n  export *\n  module * { export * }\n}\n")

  clobber_before_end(content, <<-RUBY

  s.module_map = 'PodGen_#{idx}.modulemap'
  RUBY
  )
end

# static_framework
def enhance_static_framework(content, idx, _pod_dir)
  return content if content.include?('static_framework')

  clobber_before_end(content, <<-RUBY

  s.static_framework = true
  RUBY
  )
end

# ── 工具函数 ────────────────────────────────────────────────────

# 在最后一个 end 之前插入（支持缩进）
def insert_before_end(content, insertion)
  # 从末尾查找缩进的 end 行
  idx = content.rindex(/^\s*end\s*$/)
  return content unless idx
  content.dup.insert(idx, insertion)
end

# 替换最后一个 end（支持缩进的 end 行）
def clobber_before_end(content, insertion)
  # 去掉末尾带有缩进的 end + 尾部空白
  cleaned = content.sub(/[ \t]*\n[ \t]*end\s*\z/, '')
  cleaned + insertion + "\nend\n"
end

# ══════════════════════════════════════════════════════════════════
#  1b. 生成复杂 Podfile
# ══════════════════════════════════════════════════════════════════

def generate_complex_podfile!
  output_path = File.join(BASE_DIR, 'ExampleA', 'Podfile')

  # 判断哪些 pod 有特殊特性
  has_test_spec = ENHANCEMENTS.select { |_, v| v == :test_spec }.keys
  has_vf = ENHANCEMENTS.select { |_, v| v == :vendored_framework }.keys
  has_sp = ENHANCEMENTS.select { |_, v| v == :script_phases }.keys
  has_vl = ENHANCEMENTS.select { |_, v| v == :vendored_libraries }.keys
  has_er = ENHANCEMENTS.select { |_, v| v == :extra_resources }.keys
  has_ss = ENHANCEMENTS.select { |_, v| v == :subspec }.keys
  has_mm = ENHANCEMENTS.select { |_, v| v == :module_map }.keys
  has_sf = ENHANCEMENTS.select { |_, v| v == :static_framework }.keys

  # 基础 pod 列表 — 排除有特殊特性的 pod（它们会单独声明）
  enhanced_indices = ENHANCEMENTS.keys.to_set
  all_pods = (1..150).reject { |i| enhanced_indices.include?(i) }
  debug_pods = has_er  # extra_resources pods 仅用于 Debug
  release_pods = has_sf # static_framework pods 仅用于 Release

  File.open(output_path, 'w') do |f|
    # ── 插件加载 ──
    f.puts "# Load PodGenerate plugin"
    f.puts "$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))"
    f.puts "require 'cocoapods-podgenerate'"
    f.puts "Pod::PodGenerate.activate"
    f.puts ""

    # ── 全局设置 ──
    f.puts "source 'https://cdn.cocoapods.org/'"
    f.puts ""
    f.puts "platform :ios, '15.0'"
    f.puts "use_frameworks! :linkage => :static"
    f.puts "use_modular_headers!"
    f.puts "inhibit_all_warnings!"
    f.puts ""

    # ── abstract_target 'Pods-App'（主应用） ──
    f.puts "abstract_target 'Pods-App' do"
    f.puts "  project 'Example.xcodeproj'"
    f.puts ""

    # 普通 pod（没有特殊特性）
    all_pods.each do |i|
      f.puts "  pod 'PodGen_#{i}', :path => '../generated_pods/PodGen_#{i}'"
    end

    # test_spec pods — 在 abstract_target 中直接带 :testspecs
    has_test_spec.each do |idx|
      f.puts "  pod 'PodGen_#{idx}', :path => '../generated_pods/PodGen_#{idx}', :testspecs => ['Tests']"
    end

    # vendored_framework pods
    has_vf.each do |idx|
      f.puts "  pod 'PodGen_#{idx}', :path => '../generated_pods/PodGen_#{idx}'"
    end

    # script_phases pods
    has_sp.each do |idx|
      f.puts "  pod 'PodGen_#{idx}', :path => '../generated_pods/PodGen_#{idx}'"
    end

    # vendored_libraries pods
    has_vl.each do |idx|
      f.puts "  pod 'PodGen_#{idx}', :path => '../generated_pods/PodGen_#{idx}'"
    end

    # 配置限定 pod — Debug
    debug_pods.each do |idx|
      f.puts "  pod 'PodGen_#{idx}', :path => '../generated_pods/PodGen_#{idx}', :configurations => ['Debug']"
    end

    # 配置限定 pod — Release
    release_pods.each do |idx|
      f.puts "  pod 'PodGen_#{idx}', :path => '../generated_pods/PodGen_#{idx}', :configurations => ['Release']"
    end

    # module_map pod — 关闭 modular headers
    has_mm.each do |idx|
      f.puts "  pod 'PodGen_#{idx}', :path => '../generated_pods/PodGen_#{idx}', :modular_headers => false"
    end

    # subspec pod
    has_ss.each do |idx|
      f.puts "  pod 'PodGen_#{idx}', :path => '../generated_pods/PodGen_#{idx}'"
    end

    f.puts ""

    # ── Example target（主 app，继承 abstract_target） ──
    f.puts "  target 'Example' do"
    f.puts "    # 所有 pod 继承自 abstract_target"
    f.puts "  end"
    f.puts ""

    # ── ExampleTests target（测试 target，:search_paths） ──
    f.puts "  target 'ExampleTests' do"
    f.puts "    inherit! :search_paths"
    f.puts "    # 测试 target 使用 inherit! :search_paths 只继承头文件搜索路径"
    f.puts "    # 这里不再重复声明 pod，继承自 abstract_target"
    f.puts "  end"
    f.puts "end"
    f.puts ""

    # ── 独立 target（不在 abstract_target 内） ──
    f.puts "target 'ExampleSecondTarget' do"
    f.puts "  project 'Example.xcodeproj'"
    f.puts "  # 独立的第二个 target（模拟 extension），不继承 abstract_target"
    f.puts "  pod 'PodGen_50', :path => '../generated_pods/PodGen_50'"
    f.puts "  pod 'PodGen_51', :path => '../generated_pods/PodGen_51'"
    f.puts "end"
    f.puts ""

    # ── 复杂 post_install hook ──
    f.puts "post_install do |installer|"
    f.puts "  # Pattern 1: 标准 pods_project 遍历（所有 hook 的基本操作）"
    f.puts "  installer.pods_project.targets.each do |target|"
    f.puts "    target.build_configurations.each do |config|"
    f.puts "      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'"
    f.puts "    end"
    f.puts "  end"
    f.puts ""
    f.puts "  # Pattern 2: 遍历 generated_projects（测试 F2 修复 — 跳过路径必须返回有效数组）"
    f.puts "  if installer.respond_to?(:generated_projects)"
    f.puts "    installer.generated_projects.each do |project|"
    f.puts "      project.targets.each do |target|"
    f.puts "        target.build_configurations.each do |config|"
    f.puts "          config.build_settings['ENABLE_BITCODE'] = 'NO'"
    f.puts "        end"
    f.puts "      end"
    f.puts "    end"
    f.puts "  end"
    f.puts ""
    f.puts "  # Pattern 3: 跨项目 target 依赖遍历（测试 F1 修复 — Flutter podhelper.rb 风格）"
    f.puts "  installer.pods_project.targets.each do |target|"
    f.puts "    target.dependencies.each do |dependency|"
    f.puts "      next unless dependency.target"
    f.puts "      next unless dependency.target.respond_to?(:dependencies)"
    f.puts "      # 递归遍历依赖的依赖（Flutter depends_on_flutter 的模拟）"
    f.puts "      dependency.target.dependencies.each do |sub_dep|"
    f.puts "        # 如果 dependency.target 是 nil（跨项目引用），这里会崩溃"
    f.puts "      end"
    f.puts "    end"
    f.puts "  end"
    f.puts "end"
    f.puts ""
  end

  puts "  ✅ Generated complex Podfile with abstract_target + inherit!"
  puts "     - 150 pods in abstract_target 'Pods-App'"
  puts "     - Targets: Example, ExampleTests, ExampleSecondTarget"
  puts "     - Post-install: 3 patterns (standard, generated_projects, cross-project deps)"
end

# ══════════════════════════════════════════════════════════════════
#  1c. 添加 Xcode native targets
# ══════════════════════════════════════════════════════════════════

def add_complex_targets!
  proj_dir = A_PROJ_DIR
  return unless File.exist?(proj_dir)

  project = Xcodeproj::Project.open(proj_dir)
  main_group = project.main_group
  added = []

  # 查找 Example 原始 target
  original = project.targets.find { |t| t.name == 'Example' }
  unless original
    puts "  ⚠️  Original target 'Example' not found"
    return
  end

  # ── ExampleTests（单元测试 target） ──
  unless project.targets.any? { |t| t.name == 'ExampleTests' }
    test_target = project.new_target(:unit_test_bundle, 'ExampleTests',
      original.platform_name, original.deployment_target, nil,
      'com.apple.product-type.bundle.unit-test')
    # 复制构建配置
    original.build_configurations.each do |config|
      mc = test_target.build_configurations.find { |c| c.name == config.name }
      mc&.build_settings&.merge!(config.build_settings)
    end
    # 设置 TEST_HOST
    test_target.build_configurations.each do |c|
      c.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Example.app/Example'
      c.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    end
    added << "ExampleTests (unit_test_bundle)"
  end

  # ── ExampleSecondTarget（模拟 extension） ──
  unless project.targets.any? { |t| t.name == 'ExampleSecondTarget' }
    second_target = project.new_target(:application, 'ExampleSecondTarget',
      original.platform_name, original.deployment_target, nil,
      original.product_type)
    original.build_configurations.each do |config|
      mc = second_target.build_configurations.find { |c| c.name == config.name }
      mc&.build_settings&.merge!(config.build_settings)
    end
    added << "ExampleSecondTarget (application)"
  end

  if added.empty?
    puts "  ➖ All complex targets already exist"
  else
    project.save
    puts "  ✅ Added targets: #{added.join(', ')}"
  end
end

# ══════════════════════════════════════════════════════════════════
#  Clean generated_pods  enhancements（可选）
# ══════════════════════════════════════════════════════════════════

def clean_enhancements!
  ENHANCEMENTS.each do |idx, type|
    pod_dir = File.join(PODS_DIR, "PodGen_#{idx}")
    podspec = File.join(pod_dir, "PodGen_#{idx}.podspec")
    next unless File.exist?(podspec)

    # 清理增强文件
    FileUtils.rm_rf(File.join(pod_dir, 'Tests')) if type == :test_spec
    FileUtils.rm_rf(File.join(pod_dir, 'VendoredFrameworks')) if type == :vendored_framework
    FileUtils.rm_rf(File.join(pod_dir, 'VendoredLibraries')) if type == :vendored_libraries
    FileUtils.rm_rf(File.join(pod_dir, 'ExtraAssets')) if type == :extra_resources
    FileUtils.rm_rf(File.join(pod_dir, 'UI')) if type == :subspec
    mm = File.join(pod_dir, "PodGen_#{idx}.modulemap")
    FileUtils.rm_f(mm) if type == :module_map && File.exist?(mm)
  end
  puts "  🧹 Cleaned all podspec enhancements"
end

# ══════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════

puts ""
puts "╔══════════════════════════════════════════════════════════════╗"
puts "║  Complex Podfile Test Generator                             ║"
puts "║  Enhances 150 pods + abstract_target + complex hooks        ║"
puts "╚══════════════════════════════════════════════════════════════╝"
puts ""

# 检查参数
if ARGV.include?('--clean')
  puts "━━━ Cleaning enhancements..."
  clean_enhancements!
  exit 0
end

puts "━━━ 1a. Enhancing podspecs..."
enhance_podspecs!

puts ""
puts "━━━ 1b. Generating complex Podfile..."
generate_complex_podfile!

puts ""
puts "━━━ 1c. Adding Xcode native targets..."
add_complex_targets!

puts ""
puts "✅ 完成! 运行 `cd ExampleA && ruby ../run_complex_test.rb` 执行测试"
puts ""
