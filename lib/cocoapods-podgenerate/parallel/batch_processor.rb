# frozen_string_literal: true

# [cocoapods-podgenerate]
# Batch processor that splits work items across a thread pool.
# Maintains ordering: results are returned in the same order as input items.

require 'concurrent'

module Pod
  module PodGenerate
    module Parallel
      module BatchProcessor
        # Process items in batches using a thread pool.
        # @param items [Array] list of items to process
        # @param batch_size [Integer] max items per batch (nil = auto-size)
        # @param pool [Concurrent::FixedThreadPool] the thread pool
        # @yield [item] block to process each item
        # @return [Array] results in same order as input items
        def self.process(items, pool:, batch_size: nil, &block)
          return [] if items.empty?

          results = Array.new(items.size)
          mutex = Mutex.new
          count = items.size
          completed = 0

          items.each_with_index do |item, idx|
            pool.post do
              begin
                result = block.call(item)
                mutex.synchronize { results[idx] = result }
              rescue StandardError => e
                mutex.synchronize do
                  Pod::UI.warn "[cocoapods-podgenerate] BatchProcessor error on item #{idx}: #{e.message}"
                end
              ensure
                mutex.synchronize do
                  completed += 1
                end
              end
            end
          end

          # Wait for all tasks to complete
          pool.wait_for_termination

          results
        end
      end
    end
  end
end
