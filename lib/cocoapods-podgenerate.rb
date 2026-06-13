# frozen_string_literal: true

require 'cocoapods-podgenerate/patches/installer_patch'
require 'cocoapods-podgenerate/patches/project_patch'
require 'cocoapods-podgenerate/patches/project_writer_patch'
require 'cocoapods-podgenerate/patches/analyzer_patch'
require 'cocoapods-podgenerate/patches/user_integrator_patch'
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

      # Install hook for profiler
      Pod::PodGenerate::Benchmark::Profiler.install

      Pod::UI.message '[cocoapods-podgenerate] Activated!'
    end
  end
end

# Auto-activate when loaded via `plugin` directive in Podfile
# The :pre_install hook is set up by hooks.rb, but we also support
# direct `plugin` activation which defers to when CocoaPods is loaded.
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
