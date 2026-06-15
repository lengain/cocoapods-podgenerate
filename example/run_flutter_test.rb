#!/usr/bin/env ruby
# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════
#  Unified Flutter Test Runner
#
#  合并两种 Flutter 集成模式的测试：
#    Mode A: 简单模式 — 直接添加 Flutter pod + 内联 depends_on_flutter
#    Mode B: 官方 load podhelper.rb 模式 — 加载 .ios/Flutter/podhelper.rb
#
#  运行方式:
#    ruby run_flutter_test.rb          # 运行 Mode A
#    ruby run_flutter_test.rb --load   # 运行 Mode B（load 模式）
#    ruby run_flutter_test.rb --all    # 运行所有模式
# ═══════════════════════════════════════════════════════════════════════

require 'fileutils'

BASE_DIR = File.expand_path(File.dirname(__FILE__))
A_DIR = File.join(BASE_DIR, 'ExampleA')
PODS_DIR = File.join(BASE_DIR, 'generated_pods')
FLUTTER_APP_DIR = File.join(BASE_DIR, 'flutter_app')
FLUTTER_IOS_DIR = File.join(FLUTTER_APP_DIR, '.ios', 'Flutter')
RESULT_DIR = '/tmp'

def write(path, content)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
end

# ══════════════════════════════════════════════════════════════════
#  公共步骤：重新生成 pod + 创建 Flutter 引擎/插件
# ══════════════════════════════════════════════════════════════════

def step_regenerate_pods!
  system("cd #{BASE_DIR} && ruby generate_podfile.rb > /dev/null 2>&1")
end

def step_create_flutter_pods!
  # Flutter 引擎
  FileUtils.rm_rf(File.join(PODS_DIR, 'Flutter'))
  FileUtils.mkdir_p(File.join(PODS_DIR, 'Flutter', 'Classes'))
  write(File.join(PODS_DIR, 'Flutter', 'Flutter.podspec'), <<-RUBY)
Pod::Spec.new do |s|
  s.name = 'Flutter'; s.version = '1.0.0'; s.summary = 'Flutter Engine'
  s.homepage = 'https://flutter.dev'; s.license = { :type => 'MIT' }
  s.author = { 'Flutter' => 'flutter@example.com' }
  s.source = { :git => 'https://github.com/flutter/engine.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.source_files = 'Classes/**/*.{h,m,swift}'
  s.frameworks = 'Foundation', 'UIKit'; s.requires_arc = true
end
RUBY
  write(File.join(PODS_DIR, 'Flutter', 'Classes', 'FlutterEngine.h'), '@interface FlutterEngine : NSObject @end')
  write(File.join(PODS_DIR, 'Flutter', 'Classes', 'FlutterEngine.m'), '@implementation FlutterEngine @end')

  # 插件
  %w[FlutterPluginA FlutterPluginB].each do |plugin|
    FileUtils.rm_rf(File.join(PODS_DIR, plugin))
    FileUtils.mkdir_p(File.join(PODS_DIR, plugin, 'Classes'))
    write(File.join(PODS_DIR, plugin, "#{plugin}.podspec"), <<-RUBY)
Pod::Spec.new do |s|
  s.name = '#{plugin}'; s.version = '1.0.0'; s.summary = '#{plugin}'
  s.homepage = 'https://example.com'; s.license = { :type => 'MIT' }
  s.author = { 'Example' => 'example@example.com' }
  s.source = { :git => 'https://github.com/example/#{plugin}.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.source_files = 'Classes/**/*.{h,m,swift}'
  s.dependency 'Flutter', '~> 1.0'
  s.frameworks = 'Foundation', 'UIKit'; s.requires_arc = true
end
RUBY
    write(File.join(PODS_DIR, plugin, 'Classes', "#{plugin}.h"), "@interface #{plugin} : NSObject @end")
    write(File.join(PODS_DIR, plugin, 'Classes', "#{plugin}.m"), "@implementation #{plugin} @end")
  end

  # FlutterPluginA 额外依赖 FlutterPluginB（传递依赖）
  content = File.read(File.join(PODS_DIR, 'FlutterPluginA', 'FlutterPluginA.podspec'))
  content.sub!(/^end\s*$/, "  s.dependency 'FlutterPluginB', '~> 1.0'\nend")
  File.write(File.join(PODS_DIR, 'FlutterPluginA', 'FlutterPluginA.podspec'), content)
end

def step_create_flutter_app_structure!
  FileUtils.rm_rf(FLUTTER_APP_DIR)
  write(File.join(FLUTTER_APP_DIR, 'flutter_export_environment.sh'), <<-SH)
export "FLUTTER_ROOT=/usr/local/flutter"
export "FLUTTER_APPLICATION_PATH=#{FLUTTER_APP_DIR}"
export "COCOAPODS_PARALLEL_CODE_SIGN=true"
export "FLUTTER_BUILD_DIR=build"
export "FLUTTER_FRAMEWORK_DIR=${FLUTTER_ROOT}/bin/cache/artifacts/engine/ios"
SH
  write(File.join(FLUTTER_APP_DIR, '.flutter-plugins'), <<-PLUGINS)
flutter_plugin_a=#{FLUTTER_APP_DIR}/flutter_plugin_a
flutter_plugin_b=#{FLUTTER_APP_DIR}/flutter_plugin_b
PLUGINS

  write(File.join(FLUTTER_IOS_DIR, 'podhelper.rb'), <<-RUBY)
# frozen_string_literal: true
FLUTTER_ENGINE_POD_NAME = 'Flutter'

def depends_on_flutter(target, engine_pod_name)
  target.dependencies.any? do |dependency|
    return true if dependency.name == engine_pod_name
    return true if depends_on_flutter(dependency.target, engine_pod_name)
  end
  false
end

def flutter_additional_ios_build_settings(target)
  return unless target.respond_to?(:platform_name) && target.platform_name == :ios
  target.build_configurations.each do |config|
    next unless depends_on_flutter(target, FLUTTER_ENGINE_POD_NAME)
    config.build_settings['ENABLE_BITCODE'] = 'NO'
    config.build_settings['OTHER_LDFLAGS'] = '$(inherited) -framework Flutter'
  end
end

def install_all_flutter_pods(flutter_application_path = nil)
  pod_path = flutter_application_path || File.dirname(__FILE__)
  flutter_pod = File.expand_path(File.join(pod_path, 'Flutter', 'Flutter.podspec'))
  pod 'Flutter', :podspec => flutter_pod if File.exist?(flutter_pod)
  plugins_file = File.expand_path(File.join(pod_path, '..', '..', '..', '.flutter-plugins'))
  if File.exist?(plugins_file)
    File.readlines(plugins_file).each do |line|
      next if line.strip.empty? || line.start_with?('#')
      parts = line.strip.split('=')
      next unless parts.length == 2
      name = parts[0].strip; path = parts[1].strip
      podspec_path = File.expand_path(File.join(path, 'ios', "\#{name}.podspec"))
      pod name, :path => podspec_path if File.exist?(podspec_path)
    end
  end
end

def flutter_post_install(installer, skip: false)
  return if skip
  installer.pods_project.targets.each { |t| flutter_additional_ios_build_settings(t) }
  if installer.respond_to?(:generated_projects)
    installer.generated_projects.each do |proj|
      proj.targets.each { |t| flutter_additional_ios_build_settings(t) }
    end
  end
  puts '[flutter-podhelper] ✅ flutter_post_install completed'
end
RUBY
end

def run_install!
  Dir.chdir(A_DIR) do
    FileUtils.rm_rf('Pods'); FileUtils.rm_f('Podfile.lock')
    `ruby -e '
      $stdout.sync = true; $stderr.sync = true
      $LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
      require "cocoapods"
      require "cocoapods-podgenerate"
      Pod::PodGenerate.activate
      config = Pod::Config.instance
      Pod::Installer.new(config.sandbox, config.podfile, config.lockfile).install!
    ' 2>&1`
  end
end

# ══════════════════════════════════════════════════════════════════
#  Mode A: 简单模式
# ══════════════════════════════════════════════════════════════════

def run_mode_a
  puts ""
  puts "─" * 50
  puts "Mode A: 内联 depends_on_flutter（简单模式）"
  puts "─" * 50

  # 让一些 pod 依赖 Flutter
  (36..45).each do |i|
    spec = File.join(PODS_DIR, "PodGen_#{i}", "PodGen_#{i}.podspec")
    next unless File.exist?(spec)
    content = File.read(spec)
    next if content.include?("dependency 'Flutter'")
    content.sub!(/^(\s*)end\s*$/, "\\1  s.dependency 'Flutter', '~> 1.0'\n\\1end")
    File.write(spec, content)
  end

  # Podfile
  write(File.join(A_DIR, 'Podfile'), <<-RUBY)
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'cocoapods-podgenerate'
Pod::PodGenerate.activate
source 'https://cdn.cocoapods.org/'
workspace 'Example.xcworkspace'
platform :ios, '15.0'
use_frameworks!
inhibit_all_warnings!

(1..150).each { |i| pod "PodGen_\#{i}", :path => "../generated_pods/PodGen_\#{i}" }
pod 'Flutter', :path => '../generated_pods/Flutter'
pod 'FlutterPluginA', :path => '../generated_pods/FlutterPluginA'
pod 'FlutterPluginB', :path => '../generated_pods/FlutterPluginB'

def depends_on_flutter(target, engine_pod_name)
  target.dependencies.any? do |dependency|
    return true if dependency.name == engine_pod_name
    return true if depends_on_flutter(dependency.target, engine_pod_name)
  end
  false
end

post_install do |installer|
  puts '[flutter-mode-a] post_install start'
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |c|
      next unless depends_on_flutter(t, 'Flutter')
      c.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
  if installer.respond_to?(:generated_projects)
    installer.generated_projects.each do |proj|
      proj.targets.each do |t|
        t.build_configurations.each do |c|
          next unless depends_on_flutter(t, 'Flutter')
          c.build_settings['ENABLE_BITCODE'] = 'NO'
        end
      end
    end
  end
  puts '[flutter-mode-a] ✅ post_install done'
end
RUBY

  output = run_install!
  File.write(File.join(RESULT_DIR, 'flutter_mode_a_output.txt'), output)
  exit_code = $?.exitstatus

  puts "  Exit: #{exit_code}"
  if exit_code == 0 && output.include?('[flutter-mode-a] ✅')
    puts "  ✅ Mode A passed"
    return true
  end
  puts "  ❌ Mode A failed"
  output.split("\n").select { |l| l.include?('[!]') }.each { |l| puts "     #{l}" }
  false
end

# ══════════════════════════════════════════════════════════════════
#  Mode B: load podhelper.rb 模式
# ══════════════════════════════════════════════════════════════════

def run_mode_b
  puts ""
  puts "─" * 50
  puts "Mode B: load podhelper.rb（官方集成模式）"
  puts "─" * 50

  write(File.join(A_DIR, 'Podfile'), <<-RUBY)
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'cocoapods-podgenerate'
Pod::PodGenerate.activate
source 'https://cdn.cocoapods.org/'
workspace 'Example.xcworkspace'
platform :ios, '15.0'
use_frameworks!
inhibit_all_warnings!

flutter_application_path = File.expand_path('../flutter_app', __dir__)
load File.join(flutter_application_path, '.ios', 'Flutter', 'podhelper.rb')

(1..150).each { |i| pod "PodGen_\#{i}", :path => "../generated_pods/PodGen_\#{i}" }

target 'Example' do
  install_all_flutter_pods(flutter_application_path)
end

post_install do |installer|
  flutter_post_install(installer) if defined?(flutter_post_install)
end
RUBY

  output = run_install!
  File.write(File.join(RESULT_DIR, 'flutter_mode_b_output.txt'), output)
  exit_code = $?.exitstatus

  puts "  Exit: #{exit_code}"
  if exit_code == 0 && output.include?('[flutter-podhelper] ✅')
    puts "  ✅ Mode B passed"
    return true
  end
  puts "  ❌ Mode B failed"
  output.split("\n").select { |l| l.include?('[!]') }.each { |l| puts "     #{l}" }
  false
end

# ══════════════════════════════════════════════════════════════════
#  验证跨项目依赖解析日志
# ══════════════════════════════════════════════════════════════════

def verify_resolution_log(output)
  if output.include?('[cocoapods-podgenerate] Resolved')
    count = output[/Resolved (\d+)/, 1]
    puts "  📊 跨项目依赖已解析: #{count} 个"
  else
    puts "  ⚠️  未检测到跨项目依赖解析消息（可能无跨项目依赖需要解析）"
  end
end

# ══════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════

mode = ARGV[0] || '--a'  # 默认 Mode A

puts ""
puts "╔══════════════════════════════════════════════════════════════╗"
puts "║  Unified Flutter Test Runner                                ║"
puts "║  Mode A: 内联 depends_on_flutter                             ║"
puts "║  Mode B: load podhelper.rb                                   ║"
puts "╚══════════════════════════════════════════════════════════════╝"

all_pass = true

# 步骤 1: 生成基线 pod
puts ""; puts "━━━ [准备] 重新生成 pod + Flutter 引擎/插件..."
step_regenerate_pods!
step_create_flutter_pods!
step_create_flutter_app_structure!
puts "  ✅ 准备完成"

# 运行选中的模式
if %w[--all --both -a].include?(mode)
  all_pass &= run_mode_a
  all_pass &= run_mode_b
elsif mode == '--b'
  all_pass &= run_mode_b
else
  all_pass &= run_mode_a
end

puts ""
puts "═" * 50
if all_pass
  puts "🎉 全部通过! (Exit 0)"
else
  puts "❌ 存在失败项"
end
puts ""

# 打印跨项目解析日志
outputs = []
outputs << File.read(File.join(RESULT_DIR, 'flutter_mode_a_output.txt')) if File.exist?(File.join(RESULT_DIR, 'flutter_mode_a_output.txt'))
outputs << File.read(File.join(RESULT_DIR, 'flutter_mode_b_output.txt')) if File.exist?(File.join(RESULT_DIR, 'flutter_mode_b_output.txt'))
outputs.each { |o| verify_resolution_log(o) }

exit(all_pass ? 0 : 1)
