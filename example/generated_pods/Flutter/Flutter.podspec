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
