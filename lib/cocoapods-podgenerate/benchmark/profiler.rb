# frozen_string_literal: true

# [cocoapods-podgenerate]
# Performance profiler. Hooks into Pod::Installer to time each phase.
# Output: per-phase wall-clock timing breakdown.

module Pod
  module PodGenerate
    module Benchmark
      module Profiler
        @phase_timings = []

        class << self
          def enabled?
            @enabled ||= ENV['POD_GENERATE_DEBUG'] == '1' ||
                         ENV['COCOAPODS_PODGENERATE_DEBUG'] == '1'
          end

          def enable!
            @enabled = true
          end

          def install
            return unless enabled?
            Pod::Installer.prepend(ProfilerHooks)
          end

          def record_phase(name, duration)
            @phase_timings << [name, duration]
          end

          def swap_or_default(phase_name)
            # Called from hooks: returns a timing helper or nil
          end

          def report
            return if @phase_timings.empty?
            total = @phase_timings.map(&:last).sum
            Pod::UI.puts "\n[cocoapods-podgenerate] Performance Report:"
            @phase_timings.each do |name, dur|
              pct = total > 0 ? (dur / total * 100) : 0
              Pod::UI.puts "  #{format('%-35s', name)} #{format('%.2f', dur)}s (#{format('%.1f', pct)}%)"
            end
            Pod::UI.puts "  #{'─' * 50}"
            Pod::UI.puts "  #{format('%-35s', 'TOTAL')} #{format('%.2f', total)}s"
          end
        end

        module ProfilerHooks
          def install!
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('Total install!', elapsed)
            Profiler.report
          end

          def resolve_dependencies
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('  Resolve dependencies', elapsed)
          end

          def download_dependencies
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('  Download dependencies', elapsed)
          end

          def generate_pods_project
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('  Generate Pods project', elapsed)
          end

          def integrate_user_project
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('  Integrate user project', elapsed)
          end
        end
      end
    end
  end
end
