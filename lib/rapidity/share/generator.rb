module Rapidity
  module Share
    class Generator < Base

      LUA_SCRIPTS = [:init, :check_queue, :acquire_queue]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      # Initializes a new rate limit in Redis
      #
      # Creates or updates a rate limit with the specified parameters.
      # If the limit already exists, it will be updated with new parameters.
      #
      # @param limit [Limit] limit object to initialize
      # @param ttl [Integer] time-to-live for the limit key in seconds
      # @return [Boolean] true if the limit was successfully initialized and persisted
      def init(limit, ttl: @ttl)
        result = wrap_executed_script do |r|
          r.evalsha(@lua_init, keys: [limit.name], argv: [*limit.base_params, ttl])
        end

        limit = build_limit(result)
        limit.valid? & limit.persisted?
      end

      def update(*args, **kwargs)
        init(*args, **kwargs)
      end

      # Checks the current state of the rate limit queue
      #
      # Retrieves information about the queue status for a specific limit
      #
      # @param limit_or_str [Limit, String] limit object or its name
      # @param ttl [Integer] time-to-live for the queue check
      # @return [OpenStruct] queue status information
      def check_queue(limit_or_str, ttl: @ttl)
        response = wrap_executed_script do |r|
          r.evalsha(@lua_check_queue, keys: [get_name(limit_or_str), ttl])
        end

        handle_response(response)
      end

      # Acquires tokens from the rate limit queue
      #
      # Attempts to acquire the specified number of tokens from the queue.
      # If tokens are available, they are reserved for the caller.
      #
      # @param limit_or_str [Limit, String] limit object or its name
      # @param count [Integer] number of tokens to acquire
      # @param ttl [Integer] time-to-live for the acquired tokens
      # @return [OpenStruct] result of the acquisition attempt
      def acquire_queue(limit_or_str, count: 1, ttl: @ttl)
        response = wrap_executed_script do |r|
          r.evalsha(@lua_acquire_queue, keys: [get_name(limit_or_str)], argv: [count, ttl])
        end
        handle_response(response)
      end

    end
  end
end