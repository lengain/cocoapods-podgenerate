# frozen_string_literal: true

require 'cocoapods-podgenerate/patches/installer_patch'
require 'cocoapods-podgenerate/patches/project_patch'
require 'cocoapods-podgenerate/patches/project_writer_patch'
require 'cocoapods-podgenerate/patches/analyzer_patch'
require 'cocoapods-podgenerate/patches/user_integrator_patch'
require 'cocoapods-podgenerate/patches/multi_project_generator_patch'
require 'cocoapods-podgenerate/patches/cache_analyzer_patch'
require 'cocoapods-podgenerate/parallel/thread_pool'
require 'cocoapods-podgenerate/parallel/batch_processor'
require 'cocoapods-podgenerate/benchmark/profiler'

module Pod
  module PodGenerate
    def self.activate
      # Register all patches
      Pod::PodGenerate::Patches::InstallerPatch.apply
      Pod::PodGenerate::Patches::ProjectPatch.apply
      Pod::PodGenerate::Patches::ProjectWriterPatch.apply
      Pod::PodGenerate::Patches::AnalyzerPatch.apply
      Pod::PodGenerate::Patches::UserIntegratorPatch.apply
      Pod::PodGenerate::Patches::MultiProjectGeneratorPatch.apply
      Pod::PodGenerate::Patches::CacheAnalyzerPatch.apply

      # Install hook for profiler
      Pod::PodGenerate::Benchmark::Profiler.install

      Pod::UI.message '[cocoapods-podgenerate] Activated!'
    end
  end
end

# Auto-activate when loaded via `plugin` directive in Podfile
if defined?(Pod::HooksManager)
  Pod::PodGenerate.activate
else
  # Defer activation: when CocoaPods is loaded after this file
  TracePoint.trace(:class) do |tp|
    if tp.self == Pod::HooksManager
      Pod::PodGenerate.activate
      tp.disable
    end
  end
end
