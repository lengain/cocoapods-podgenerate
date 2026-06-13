# frozen_string_literal: true

module Pod
  class Command
    class Podgenerate < Command
      self.summary = 'Run pod install with PodGenerate optimizations'
      self.description = <<-DESC
        Speeds up pod install for large projects (200+ pods) by enabling
        parallel processing, optimized dependency analysis, and incremental
        project generation.
      DESC

      self.arguments = []

      def self.options
        [
          ['--debug', 'Enable verbose profiling output and detailed timing logs']
        ].concat(super)
      end

      def initialize(argv)
        @debug = argv.flag?('debug', false)
        super
      end

      def run
        Pod::PodGenerate.activate

        if @debug
          Pod::UI.puts '[cocoapods-podgenerate] Debug mode enabled — verbose profiling output will be shown.'
          ENV['COCOAPODS_PODGENERATE_DEBUG'] = '1'
        end

        # Delegate to the standard install command
        install_command = Pod::Command::Install.new(CLAide::ARGV.new([]))
        install_command.run
      end
    end
  end
end
