  Pod::Spec.new do |s|
    s.name             = 'PodGen_4'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_4 - [BaseUtility] 底层基础工具库，提供核心基础设施能力'
    s.description      = <<-DESC
        PodGen_4 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: BaseUtility. 底层基础工具库，提供核心基础设施能力
    DESC
    s.homepage         = 'https://github.com/example/PodGen_4'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_4.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_4Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true

  end
