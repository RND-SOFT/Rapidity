module Rapidity
  module Share
    class Limit

      attr_reader :name, :count, :interval, :queue_lengt

      def initialize(name, count, interval, queue_lengt: 0)
        @name = name.to_s
        @count = count.to_i
        @queue_lengt = queue_lengt.to_i
        
        @interval = interval.to_i
        raise ArgumentError.new("count must be a integer") unless @count.is_a?(Integer)
        raise ArgumentError.new("count must be a greater than 0") unless @count > 0
        @count = count

        raise ArgumentError.new("interval must be a integer") unless @interval.is_a?(Integer)
        raise ArgumentError.new("interval must be a greater than 0") unless @interval > 0
        @interval = interval
      end
    end
  end
end