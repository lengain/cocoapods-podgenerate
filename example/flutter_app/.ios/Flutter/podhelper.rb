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
    podspec_path = File.expand_path(File.join(plugin_path, 'ios', "#{plugin_name}.podspec"))
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
