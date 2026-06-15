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
