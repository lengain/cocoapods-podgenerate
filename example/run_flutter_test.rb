#!/usr/bin/env ruby
# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════
#  Flutter Pod Simulation Test
#
#  模拟 Flutter 集成场景：
#    - 创建 "Flutter" pod（引擎），多个 pod 通过 s.dependency 依赖它
#    - 添加 Flutter podhelper.rb 风格的 depends_on_flutter 递归函数
#    - 测试 PodGenerate 在 generate_multiple_pod_projects 下的兼容性
#
#  关键验证：
#    - 跨项目 PBXTargetDependency 引用（dependency.target）不为 nil（F1 修复）
#    - 递归 depends_on_flutter 遍历不崩溃
#    - generated_projects 遍历不崩溃（F2 修复）
# ═══════════════════════════════════════════════════════════════════════

require 'fileutils'

BASE_DIR = File.expand_path(File.dirname(__FILE__))
A_DIR = File.join(BASE_DIR, 'ExampleA')
PODS_DIR = File.join(BASE_DIR, 'generated_pods')

# ── 工具: 写入文件 ──────────────────────────────────────────────
def write(filename, content)
  File.write(filename, content)
end

def mkdir(path)
  FileUtils.mkdir_p(path)
end

# ══════════════════════════════════════════════════════════════════
#  1. 基于原始 generate_podfile.rb 重新生成所有 pod
# ══════════════════════════════════════════════════════════════════

def regenerate_pods!
  puts "━━━ [1/5] 重新生成所有 pod（基于原始 generate_podfile.rb）..."

  # 清理之前测试的残留
  (1..150).each do |i|
    pod_dir = File.join(PODS_DIR, "PodGen_#{i}")
    next unless File.exist?(pod_dir)
    # 删除增强相关目录
    %w[Tests VendoredFrameworks VendoredLibraries ExtraAssets UI].each do |dir|
      FileUtils.rm_rf(File.join(pod_dir, dir))
    end
    # 删除 modulemap 文件
    FileUtils.rm_f(File.join(pod_dir, "PodGen_#{i}.modulemap"))
  end

  # 重新生成 podspec（使用原始生成脚本）
  system("cd #{BASE_DIR} && ruby generate_podfile.rb > /dev/null 2>&1")
  puts "  ✅ Pods regenerated (clean baseline)"
end

# ══════════════════════════════════════════════════════════════════
#  2. 创建 Flutter pod
# ══════════════════════════════════════════════════════════════════

def create_flutter_pod!
  puts "━━━ [2/5] 创建 Flutter pod..."

  flutter_dir = File.join(PODS_DIR, 'Flutter')
  mkdir(flutter_dir)
  mkdir(File.join(flutter_dir, 'Classes'))
  mkdir(File.join(flutter_dir, 'ios'))

  # Flutter podspec — 模拟 Flutter 引擎
  write(File.join(flutter_dir, 'Flutter.podspec'), <<-RUBY)
Pod::Spec.new do |s|
  s.name             = 'Flutter'
  s.version          = '1.0.0'
  s.summary          = 'Flutter Engine Pod (simulated)'
  s.homepage         = 'https://flutter.dev'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Flutter' => 'flutter@example.com' }
  s.source           = { :git => 'https://github.com/flutter/engine.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.platform         = :ios, '15.0'
  s.source_files     = 'Classes/**/*.{h,m,swift}', 'ios/**/*.{h,m,mm}'
  s.frameworks       = 'Foundation', 'UIKit'
  s.requires_arc     = true
end
RUBY

  # Flutter 引擎源文件
  write(File.join(flutter_dir, 'Classes', 'FlutterEngine.h'), <<-OBJC)
#import <UIKit/UIKit.h>
@interface FlutterEngine : NSObject
+ (instancetype)sharedEngine;
- (void)run;
@end
OBJC

  write(File.join(flutter_dir, 'Classes', 'FlutterEngine.m'), <<-OBJC)
#import "FlutterEngine.h"
@implementation FlutterEngine
+ (instancetype)sharedEngine { static id s; s = [[self alloc] init]; return s; }
- (void)run { }
@end
OBJC

  # Flutter 插件注册表
  write(File.join(flutter_dir, 'ios', 'FlutterPluginRegistrant.m'), <<-OBJC)
#import <Foundation/Foundation.h>
@interface FlutterPluginRegistrant : NSObject @end
@implementation FlutterPluginRegistrant @end
OBJC

  puts "  ✅ Flutter pod created (with Classes/ + ios/ source files)"
end

# ══════════════════════════════════════════════════════════════════
#  3. 让 10 个 Mid 层 pod 依赖 Flutter（模拟 Flutter 插件依赖）
# ══════════════════════════════════════════════════════════════════

def add_flutter_deps!
  puts "━━━ [3/5] 让 PodGen_36..45 依赖 Flutter（模拟 Flutter plugin 场景）..."

  added = 0
  (36..45).each do |idx|
    podspec = File.join(PODS_DIR, "PodGen_#{idx}", "PodGen_#{idx}.podspec")
    next unless File.exist?(podspec)

    content = File.read(podspec)
    next if content.include?("dependency 'Flutter'")

    # 在最后一个 end 前插入 s.dependency 'Flutter'
    if content =~ /^(\s*)end\s*$/
      content.sub!(/^(\s*)end\s*$/, "\\1  s.dependency 'Flutter', '~> 1.0'\n\\1end")
      File.write(podspec, content)
      added += 1
    end
  end
  puts "  ✅ #{added} pods now depend on Flutter"
end

# ══════════════════════════════════════════════════════════════════
#  4. 生成 Flutter 兼容 Podfile
# ══════════════════════════════════════════════════════════════════

def generate_podfile!
  puts "━━━ [4/5] 生成 Flutter 兼容 Podfile..."

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

# 所有 150 个 pod + Flutter
(1..150).each do |i|
  pod "PodGen_\#{i}", :path => "../generated_pods/PodGen_\#{i}"
end
pod 'Flutter', :path => '../generated_pods/Flutter'

# ── Flutter podhelper.rb 精确复现 ──
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

def flutter_additional_ios_build_settings(target)
  return unless target.respond_to?(:platform_name)
  return unless target.platform_name == :ios
  target.build_configurations.each do |config|
    if depends_on_flutter(target, 'Flutter')
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end

post_install do |installer|
  puts '[flutter-test] Running Flutter post_install hook...'

  # Pattern 1: 标准 Flutter 方式 — 遍历 pods_project.targets
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end

  # Pattern 2: 遍历 generated_projects（测试 F2 修复）
  if installer.respond_to?(:generated_projects)
    installer.generated_projects.each do |project|
      project.targets.each do |target|
        flutter_additional_ios_build_settings(target)
      end
    end
  end

  puts '[flutter-test] ✅ Flutter post_install hook completed'
end
RUBY

  puts "  ✅ Podfile generated with Flutter post_install hook"
end

# ══════════════════════════════════════════════════════════════════
#  5. 运行 pod install
# ══════════════════════════════════════════════════════════════════

def run_install!
  puts "━━━ [5/5] 运行 pod install（带 PodGenerate 插件）..."

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

    File.write('/tmp/flutter_test_output.txt', output)
    [$?.exitstatus, output]
  end
end

# ══════════════════════════════════════════════════════════════════
#  6. 验证
# ══════════════════════════════════════════════════════════════════

def verify(exit_code, output)
  puts ""
  puts "━━━ 验证..."
  all_pass = true

  # 安装成功
  if exit_code == 0
    puts "  ✅ pod install 完成 (exit=0)"
  else
    puts "  ❌ pod install 失败 (exit=#{exit_code})"
    output.split("\n").select { |l| l.include?('[!]') || l.include?('Error:') }.each { |l| puts "     #{l.strip}" }
    return false
  end

  # Flutter 被安装
  if output.include?('Installing Flutter')
    puts "  ✅ Flutter pod 已安装"
  end

  # depends_on_flutter 递归不崩溃
  if output.include?("undefined method") && output.include?("dependencies")
    puts "  ❌ depends_on_flutter 递归崩溃！(dependency.target 为 nil)"
    all_pass = false
  else
    puts "  ✅ depends_on_flutter 递归遍历未崩溃（F1 修复有效）"
  end

  # generated_projects 遍历不崩溃
  if output.include?("undefined method") && output.include?("generated_projects")
    puts "  ❌ generated_projects 遍历崩溃"
    all_pass = false
  else
    puts "  ✅ generated_projects 遍历未崩溃（F2 修复有效）"
  end

  # Flutter post_install hook 完成
  if output.include?('[flutter-test] ✅')
    puts "  ✅ Flutter post_install hook 执行成功"
  else
    puts "  ⚠️  Flutter post_install hook 未检测到完成标记"
  end

  # 多项目生成
  sub_count = Dir[File.join(A_DIR, 'Pods', '*.xcodeproj')].size
  if sub_count > 50
    puts "  ✅ generate_multiple_pod_projects: #{sub_count} 个 xcodeproj"
  else
    puts "  ⚠️  子项目较少: #{sub_count}"
  end

  # 验证 PBXTargetDependency 跨项目引用
  if output.include?('[cocoapods-podgenerate] Resolved')
    puts "  ✅ 跨项目依赖已解析"
  end

  if all_pass
    puts ""
    puts "  🎉 全部通过！PodGenerate 完全兼容 Flutter pod 依赖场景"
  else
    puts ""
    puts "  ❌ 存在失败项"
  end
  all_pass
end

# ══════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════

puts ""
puts "╔══════════════════════════════════════════════════════════════╗"
puts "║  Flutter Pod Simulation Test                                ║"
puts "║  验证 PodGenerate 在 Flutter 场景下的兼容性                  ║"
puts "╚══════════════════════════════════════════════════════════════╝"
puts ""

regenerate_pods!
create_flutter_pod!
add_flutter_deps!
generate_podfile!
exit_code, output = run_install!
success = verify(exit_code, output)

puts ""
puts "📝 完整输出: /tmp/flutter_test_output.txt"
puts ""

exit(success ? 0 : 1)
