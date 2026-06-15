Pod::Spec.new do |s|
  s.name             = 'FlutterPluginB'
  s.version          = '1.0.0'
  s.summary          = 'FlutterPluginB'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Example' => 'example@example.com' }
  s.source           = { :git => 'https://github.com/example/FlutterPluginB.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.source_files     = 'Classes/**/*.{h,m,swift}'
  s.dependency 'Flutter', '~> 1.0'
  s.dependency 'PodGen_36', '~> 1.0'  # 还依赖一个普通 pod
  s.frameworks       = 'Foundation', 'UIKit'
  s.requires_arc     = true
end
