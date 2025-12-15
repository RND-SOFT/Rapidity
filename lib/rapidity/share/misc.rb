module Rapidity
  module Share
    class Limit

      attr_reader :name, :max_tokens, :tokens, :interval, :max_queue, :queue, :last_used, :rate

      def initialize(name, max_tokens, interval, queue: nil, validate: true, 
          tokens: nil, max_queue: 0, last_used: nil, rate: nil)
        @name = name.to_s
        @max_tokens = max_tokens.to_i
        @tokens = tokens.to_i
        @interval = interval.to_i
        @queue = queue.to_i
        @max_queue = max_queue.to_i
        @last_used = last_used.to_i
        @rate = rate.to_i == 0 ? @max_tokens.to_f/@interval.to_f : rate

        validate_parameters! if validate
      end

      def self.from_hash(name, **kwargs)
        max_tokens = kwargs.delete(:max_tokens)
        interval = kwargs.delete(:interval)
        self.new(name, max_tokens, interval, **kwargs)
      end

      def persisted?
        @last_used > 0
      end

      def valid?
        @max_tokens > 0 && @interval > 0
      end

      def base_params
        [max_tokens, interval, max_queue,]
      end

      private

      def validate_parameters!
        raise ArgumentError, "max_tokens must be greater than 0" unless @max_tokens > 0
        raise ArgumentError, "interval must be greater than 0" unless @interval > 0
      end

    end
  end
end