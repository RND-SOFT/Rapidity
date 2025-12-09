module Rapidity
  module Share
    class Limit

      attr_reader :name, :count, :interval, :queue

      def initialize(name, count, interval, queue: 0)
        @name = name.to_s
        @count = count.to_i
        @interval = interval.to_i
        @queue = queue.to_i

        validate_parameters!
      end

      private

      def validate_parameters!
        raise ArgumentError, "count must be greater than 0" unless @count > 0
        raise ArgumentError, "interval must be greater than 0" unless @interval > 0
      end
    end
  end
end