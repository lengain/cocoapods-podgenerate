# frozen_string_literal: true

# [cocoapods-podgenerate]
# Performance profiler. Hooks into Pod::Installer to time each phase.
# Output: per-phase wall-clock timing breakdown with sub-step detail.

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
            Pod::Installer.prepend(ProfilerSubSteps)
          end

          def record_phase(name, duration)
            @phase_timings << [name, duration]
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
            @phase_timings.clear
          end
        end

        # Top-level step hooks (v0.1.0)
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

        # Sub-step timing hooks (v0.1.2)
        module ProfilerSubSteps
          def stage_sandbox(sandbox, pod_targets)
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('    Stage sandbox', elapsed) if elapsed > 0.01
          end

          def analyze_project_cache
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            result = super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('    Analyze project cache', elapsed) if elapsed > 0.01
            result
          end

          def create_and_save_projects(*args)
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('    Create and save projects', elapsed) if elapsed > 0.01
          end

          def update_project_cache(cache_analysis_result, target_installation_results)
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('    Update project cache', elapsed) if elapsed > 0.01
          end

          def write_lockfiles
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super
          ensure
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            Profiler.record_phase('  Write lockfiles', elapsed)
          end
        end
      end
    end
  end
end
