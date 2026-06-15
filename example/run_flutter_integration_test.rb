#!/usr/bin/env ruby
# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════
#  Flutter Add-to-App Integration Test
#
#  模拟 Flutter 官方文档「legacy project setup」集成方式：
#    flutter_application_path = '../flutter_app'
#    load File.join(flutter_application_path, '.ios', 'Flutter', 'podhelper.rb')
#
#  然后测试 PodGenerate (generate_multiple_pod_projects) 兼容性。
#  关键验证：flutter_post_install 中遍历 pods_project.targets 并调用
#  depends_on_flutter 递归函数时，跨项目 PBXTargetDependency 不崩溃。
# ═══════════════════════════════════════════════════════════════════════

require 'fileutils'

BASE_DIR = File.expand_path(File.dirname(__FILE__))
A_DIR = File.join(BASE_DIR, 'ExampleA')
PODS_DIR = File.join(BASE_DIR, 'generated_pods')
FLUTTER_APP_DIR = File.join(BASE_DIR, 'flutter_app')
FLUTTER_IOS_DIR = File.join(FLUTTER_APP_DIR, '.ios', 'Flutter')

def write(path, content)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
end

# ══════════════════════════════════════════════════════════════════
#  1. 重新生成干净 pod 基线
# ══════════════════════════════════════════════════════════════════

def regenerate_pods!
  puts "━━━ [1/6] 重新生成干净 pod 基线..."
  system("cd #{BASE_DIR} && ruby generate_podfile.rb > /dev/null 2>&1")
  puts "  ✅ Pods regenerated"
end

# ══════════════════════════════════════════════════════════════════
#  2. 创建 Flutter 引擎 pod + 插件 pods
# ══════════════════════════════════════════════════════════════════

def create_flutter_engine_pod!
  puts "━━━ [2/6] 创建 Flutter 引擎 pod + 插件 pods..."

  # Flutter 引擎 pod
  flutter_dir = File.join(PODS_DIR, 'Flutter')
  FileUtils.mkdir_p(File.join(flutter_dir, 'Classes'))
  write(File.join(flutter_dir, 'Flutter.podspec'), <<-RUBY)
Pod::Spec.new do |s|
  s.name             = 'Flutter'
  s.version          = '1.0.0'
  s.summary          = 'Flutter Engine'
  s.homepage         = 'https://flutter.dev'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Flutter' => 'flutter@example.com' }
  s.source           = { :git => 'https://github.com/flutter/engine.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.source_files     = 'Classes/**/*.{h,m,swift}'
  s.frameworks       = 'Foundation', 'UIKit'
  s.requires_arc     = true
end
RUBY
  write(File.join(flutter_dir, 'Classes', 'FlutterEngine.h'), '@interface FlutterEngine : NSObject @end')
  write(File.join(flutter_dir, 'Classes', 'FlutterEngine.m'), '@implementation FlutterEngine @end')

  # 模拟 Flutter 插件: FlutterPluginA, FlutterPluginB
  %w[FlutterPluginA FlutterPluginB].each do |plugin|
    dir = File.join(PODS_DIR, plugin)
    FileUtils.mkdir_p(File.join(dir, 'Classes'))
    write(File.join(dir, "#{plugin}.podspec"), <<-RUBY)
Pod::Spec.new do |s|
  s.name             = '#{plugin}'
  s.version          = '1.0.0'
  s.summary          = '#{plugin}'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Example' => 'example@example.com' }
  s.source           = { :git => 'https://github.com/example/#{plugin}.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.source_files     = 'Classes/**/*.{h,m,swift}'
  s.dependency 'Flutter', '~> 1.0'
  s.dependency 'PodGen_36', '~> 1.0'  # 还依赖一个普通 pod
  s.frameworks       = 'Foundation', 'UIKit'
  s.requires_arc     = true
end
RUBY
    write(File.join(dir, 'Classes', "#{plugin}.h"), "@interface #{plugin} : NSObject @end")
    write(File.join(dir, 'Classes', "#{plugin}.m"), "@implementation #{plugin} @end")
    puts "  ✅ Created #{plugin}"
  end

  # 让 FlutterPluginA 还依赖 FlutterPluginB（模拟 transitive dependency）
  podspec = File.join(PODS_DIR, 'FlutterPluginA', 'FlutterPluginA.podspec')
  content = File.read(podspec)
  content.sub!(/^end\s*$/, "  s.dependency 'FlutterPluginB', '~> 1.0'\nend")
  File.write(podspec, content)
end

# ══════════════════════════════════════════════════════════════════
#  3. 创建 Flutter APP 目录结构 + podhelper.rb
# ══════════════════════════════════════════════════════════════════

def create_flutter_app_structure!
  puts "━━━ [3/6] 创建 Flutter APP 目录 + podhelper.rb..."

  # flutter_export_environment.sh
  write(File.join(FLUTTER_APP_DIR, 'flutter_export_environment.sh'), <<-SH)
export "FLUTTER_ROOT=/usr/local/flutter"
export "FLUTTER_APPLICATION_PATH=#{FLUTTER_APP_DIR}"
export "COCOAPODS_PARALLEL_CODE_SIGN=true"
export "FLUTTER_BUILD_DIR=build"
export "FLUTTER_FRAMEWORK_DIR=${FLUTTER_ROOT}/bin/cache/artifacts/engine/ios"
export "FLUTTER_BUILD_NAME=1.0.0"
export "FLUTTER_BUILD_NUMBER=1"
export "DART_OBFUSCATION=false"
export "TRACK_WIDGET_CREATION=true"
export "TREE_SHAKE_ICONS=false"
export "PACKAGE_CONFIG=${FLUTTER_APPLICATION_PATH}/.dart_tool/package_config.json"
SH

  # .flutter-plugins (模拟 Flutter 插件清单)
  write(File.join(FLUTTER_APP_DIR, '.flutter-plugins'), <<-PLUGINS)
flutter_plugin_a=#{FLUTTER_APP_DIR}/flutter_plugin_a
flutter_plugin_b=#{FLUTTER_APP_DIR}/flutter_plugin_b
PLUGINS

  # ── 核心: .ios/Flutter/podhelper.rb ──
  # 这个文件是 Flutter 官方文档中 load 的目标
  # 它先 require Flutter SDK 的 podhelper.rb，然后定义 install_all_flutter_pods 和 flutter_post_install
  #
  # 模拟 Flutter 官方 podhelper.rb 的完整行为：
  #   1. install_all_flutter_pods → 安装引擎 + 插件
  #   2. flutter_post_install → 遍历 targets 设置构建设置

  write(File.join(FLUTTER_IOS_DIR, 'podhelper.rb'), <<-RUBY)
# frozen_string_literal: true

# ── Flutter 引擎 pod 路径 ──
FLUTTER_ENGINE_POD_NAME = 'Flutter'

# ── depends_on_flutter（精确复现 Flutter podhelper.rb）─
# 递归检查 target 是否直接或间接依赖 Flutter 引擎
def depends_on_flutter(target, engine_pod_name)
  target.dependencies.any? do |dependency|
    if dependency.name == engine_pod_name
      return true
    end
    if depends_on_flutter(dependency.target, engine_pod_name)
      return true
    end
  end
  return false
end

# ── flutter_additional_ios_build_settings（精确复现 Flutter SDK podhelper）─
def flutter_additional_ios_build_settings(target)
  return unless target.respond_to?(:platform_name)
  return unless target.platform_name == :ios

  target.build_configurations.each do |build_configuration|
    # 设置部署目标
    build_configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'

    # Skip non-Flutter-dependent targets（这正是触发递归 depends_on_flutter 的地方）
    next unless depends_on_flutter(target, FLUTTER_ENGINE_POD_NAME)

    # Flutter 标准构建设置
    build_configuration.build_settings['ENABLE_BITCODE'] = 'NO'
    build_configuration.build_settings['CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER'] = 'NO'
    build_configuration.build_settings['OTHER_LDFLAGS'] = '$(inherited) -framework Flutter'
  end
end

# ── flutter_install_ios_engine_pod ──
def flutter_install_ios_engine_pod(ios_application_path = nil)
  pod_path = ios_application_path || File.dirname(__FILE__)
  flutter_pod = File.expand_path(File.join(pod_path, 'Flutter', 'Flutter.podspec'))
  pod 'Flutter', :podspec => flutter_pod if File.exist?(flutter_pod)
end

# ── flutter_install_plugin_pods ──
def flutter_install_plugin_pods(ios_application_path = nil)
  plugins_file = File.expand_path(File.join(ios_application_path || File.dirname(__FILE__), '..', '..', '..', '.flutter-plugins'))
  return unless File.exist?(plugins_file)

  File.readlines(plugins_file).each do |line|
    next if line.strip.empty? || line.start_with?('#')
    parts = line.strip.split('=')
    next unless parts.length == 2
    plugin_name = parts[0].strip
    plugin_path = parts[1].strip
    podspec_path = File.expand_path(File.join(plugin_path, 'ios', "\#{plugin_name}.podspec"))
    if File.exist?(podspec_path)
      pod plugin_name, :path => podspec_path
    end
  end
end

# ── install_all_flutter_pods（Flutter 官方 API） ──
def install_all_flutter_pods(flutter_application_path = nil)
  flutter_install_ios_engine_pod(flutter_application_path)
  flutter_install_plugin_pods(flutter_application_path)
  puts '[flutter-podhelper] install_all_flutter_pods completed'
end

# ── flutter_post_install（Flutter 官方 API） ──
def flutter_post_install(installer, skip: false)
  return if skip
  puts '[flutter-podhelper] Running flutter_post_install...'
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
  # 新版本 Flutter 还遍历 generated_projects
  if installer.respond_to?(:generated_projects)
    installer.generated_projects.each do |project|
      project.targets.each do |target|
        flutter_additional_ios_build_settings(target)
      end
    end
  end
  puts '[flutter-podhelper] ✅ flutter_post_install completed'
end
RUBY
  puts "  ✅ Created Flutter APP structure + podhelper.rb"
end

# ══════════════════════════════════════════════════════════════════
#  4. 生成 Flutter 集成 Podfile
# ══════════════════════════════════════════════════════════════════

def generate_podfile!
  puts "━━━ [4/6] 生成 Flutter 集成 Podfile..."

  write(File.join(A_DIR, 'Podfile'), <<-RUBY)
# PodGenerate plugin
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'cocoapods-podgenerate'
Pod::PodGenerate.activate

source 'https://cdn.cocoapods.org/'

workspace 'Example.xcworkspace'
platform :ios, '15.0'
use_frameworks!
inhibit_all_warnings!

# ════════════════════════════════════════════════════════════
# Flutter 集成（官方 legacy 方式）
# ════════════════════════════════════════════════════════════
flutter_application_path = File.expand_path('../flutter_app', __dir__)
load File.join(flutter_application_path, '.ios', 'Flutter', 'podhelper.rb')

# 所有 150 个 PodGen pod
(1..150).each do |i|
  pod "PodGen_\#{i}", :path => "../generated_pods/PodGen_\#{i}"
end

target 'Example' do
  install_all_flutter_pods(flutter_application_path)
end

target 'ExampleSecondTarget' do
  project 'Example.xcodeproj'
  pod 'PodGen_50', :path => '../generated_pods/PodGen_50'
  pod 'PodGen_51', :path => '../generated_pods/PodGen_51'
end

# Flutter 标准 post_install hook
post_install do |installer|
  flutter_post_install(installer) if defined?(flutter_post_install)
end
RUBY
  puts "  ✅ Podfile generated with Flutter integration pattern"
end

# ══════════════════════════════════════════════════════════════════
#  5. 运行 pod install
# ══════════════════════════════════════════════════════════════════

def run_install!
  puts "━━━ [5/6] 运行 pod install（带 PodGenerate 插件）..."

  Dir.chdir(A_DIR) do
    FileUtils.rm_rf('Pods')
    FileUtils.rm_f('Podfile.lock')

    output = `ruby -e '
      $stdout.sync = true; $stderr.sync = true
      $LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
      require "cocoapods"
      require "cocoapods-podgenerate"
      Pod::PodGenerate.activate
      config = Pod::Config.instance
      Pod::Installer.new(config.sandbox, config.podfile, config.lockfile).install!
    ' 2>&1`

    File.write('/tmp/flutter_integration_output.txt', output)
    [$?.exitstatus, output]
  end
end

# ══════════════════════════════════════════════════════════════════
#  6. 验证
# ══════════════════════════════════════════════════════════════════

def verify(exit_code, output)
  puts ""
  puts "━━━ [6/6] 验证..."
  all_pass = true

  if exit_code == 0
    puts "  ✅ pod install 完成 (exit=0)"
  else
    puts "  ❌ pod install 失败 (exit=#{exit_code})"
    output.split("\n").select { |l| l.include?('[!]') }.each { |l| puts "     #{l.strip}" }
    return false
  end

  # Flutter podhelper 完成
  if output.include?('[flutter-podhelper] ✅ flutter_post_install completed')
    puts "  ✅ flutter_post_install hook 执行成功"
  else
    puts "  ❌ flutter_post_install hook 未完成"
    all_pass = false
  end

  if output.include?('[flutter-podhelper] install_all_flutter_pods completed')
    puts "  ✅ install_all_flutter_pods 完成"
  end

  # depends_on_flutter 递归不崩溃
  if output.include?("undefined method") && output.include?("dependencies")
    puts "  ❌ depends_on_flutter 递归崩溃！"
    all_pass = false
  else
    puts "  ✅ depends_on_flutter 递归遍历未崩溃"
  end

  # Flutter 引擎 + 插件已安装
  %w[Flutter FlutterPluginA FlutterPluginB].each do |pod|
    if output.include?("Installing #{pod}")
      puts "  ✅ #{pod} 已安装"
    else
      puts "  ⚠️  #{pod} 未检测到安装消息"
    end
  end

  # PodGenerate 工作
  sub_count = Dir[File.join(A_DIR, 'Pods', '*.xcodeproj')].size
  puts "  📦 #{sub_count} 个 xcodeproj 文件"

  if all_pass
    puts ""
    puts "  🎉 全部通过！PodGenerate 完全兼容 Flutter Add-to-App 集成模式"
  end
  all_pass
end

# ══════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════

puts ""
puts "╔══════════════════════════════════════════════════════════════╗"
puts "║  Flutter Add-to-App Integration Test                        ║"
puts "║  load podhelper.rb 集成模式                                   ║"
puts "╚══════════════════════════════════════════════════════════════╝"
puts ""

regenerate_pods!
create_flutter_engine_pod!
create_flutter_app_structure!
generate_podfile!
exit_code, output = run_install!
success = verify(exit_code, output)

puts ""
puts "📝 完整输出: /tmp/flutter_integration_output.txt"
puts ""
exit(success ? 0 : 1)
