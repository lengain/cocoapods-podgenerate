  Pod::Spec.new do |s|
    s.name             = 'PodGen_121'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_121 - [HighBusiness] 高层业务模块，编排多个中层组件实现完整业务场景'
    s.description      = <<-DESC
        PodGen_121 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: HighBusiness. 高层业务模块，编排多个中层组件实现完整业务场景
    DESC
    s.homepage         = 'https://github.com/example/PodGen_121'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_121.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_121Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_36', '~> 1.0'
  s.dependency 'PodGen_37', '~> 1.0'
  s.dependency 'PodGen_51', '~> 1.0'
  s.dependency 'PodGen_52', '~> 1.0'
  s.dependency 'PodGen_53', '~> 1.0'
  s.dependency 'PodGen_68', '~> 1.0'
  s.dependency 'PodGen_69', '~> 1.0'
  s.dependency 'PodGen_70', '~> 1.0'
  s.dependency 'PodGen_84', '~> 1.0'
  s.dependency 'PodGen_85', '~> 1.0'
  s.dependency 'PodGen_3', '~> 1.0'
  s.dependency 'PodGen_12', '~> 1.0'
  s.dependency 'PodGen_16', '~> 1.0'
  s.dependency 'PodGen_21', '~> 1.0'
  s.dependency 'PodGen_25', '~> 1.0'
  s.dependency 'PodGen_29', '~> 1.0'
  s.dependency 'PodGen_34', '~> 1.0'
  end
