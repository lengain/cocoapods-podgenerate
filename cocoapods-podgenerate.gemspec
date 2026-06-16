# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'cocoapods-podgenerate'
  spec.version = '0.1.10'
  spec.summary       = 'Speeds up CocoaPods install for large projects (200+ pods)'
  spec.description   = 'A CocoaPods plugin that accelerates pod install for large-scale projects with 200+ pods by introducing parallel processing, optimized dependency analysis, incremental project generation, and multi-project parallel saving.'
  spec.authors       = ['PodGenerate Team']
  spec.homepage      = 'https://github.com/lengain/cocoapods-podgenerate'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0'

  spec.files         = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']

  spec.add_dependency 'cocoapods', '>= 1.10.0'
  spec.add_dependency 'concurrent-ruby', '~> 1.1'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
