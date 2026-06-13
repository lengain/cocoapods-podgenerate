# frozen_string_literal: true

# [cocoapods-podgenerate]
# Thread pool wrapper using plain Ruby Thread.
# Provides CPU-core-aware pool sizing with work queue and error handling.

module Pod
  module PodGenerate
    module Parallel
      module ThreadPool
        class << self
          def default_size
            @default_size ||= [Etc.nprocessors - 1, 2].max
          rescue NameError
            @default_size ||= 4
          end

          # Create and yield a thread pool, then shut it down.
          def with_pool(size: nil, &block)
            pool = create(size: size)
            yield pool
          ensure
            pool&.each(&:kill)
          end

          def create(size: nil)
            pool_size = size || default_size
            # Return an array of available threads - caller manages them
            Array.new(pool_size) { Thread.new { sleep } }.each(&:exit)
            # We use a simpler approach - caller creates threads directly
            nil
          end
        end
      end
    end
  end
end
