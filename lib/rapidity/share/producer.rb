module Rapidity
  module Share
    class Producer < Base

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
        limit.valid? && limit.persisted?
      end

      def update(*args, **kwargs)
        init(*args, **kwargs)
      end

      # Checks the current state of the rate limit semaphore for `Feedback-Driven Flow Control` 
      #
      # Retrieves information about the semaphore status for a specific limit
      #
      # @param limit_or_str [Limit, String] limit object or its name
      # @param ttl [Integer] time-to-live for the semaphore check
      # @return [OpenStruct] semaphore status information
      def check_queue(limit_or_str, ttl: @ttl)
        response = wrap_executed_script do |r|
          r.evalsha(@lua_check_queue, keys: [get_name(limit_or_str)], argv: [ttl])
        end

        handle_response(response)
      end

      # Acquires tokens from the rate limit semaphore for  `Feedback-Driven Flow Control` 
      #
      # Attempts to acquire the specified number of tokens from the semaphore.
      # If tokens are available, they are reserved for the caller.
      #
      # @param list_limits_or_str [Array<Limit>, Array<String>] array of limit objects or limit names
      # @param count [Integer] number of tokens to acquire
      # @param ttl [Integer] time-to-live for the acquired tokens
      # @return [OpenStruct] result of the acquisition attempt
      def acquire_queue(list_limits_or_str, count: 1, ttl: @ttl)
        list_limits_or_str = [list_limits_or_str] unless list_limits_or_str.is_a?(Array)
        
        raise ArgumentError, "limits list is empty" if list_limits_or_str.empty?
        raise ArgumentError, "count must be positive" unless count > 0


        limits = if list_limits_or_str[0].is_a?(Limit)
          list_limits_or_str.map {|it| it.name}
        else
          list_limits_or_str
        end

        response = wrap_executed_script do |r|
          r.evalsha(@lua_acquire_queue, keys: [*limits], argv: [count, ttl])
        end
        handle_response(response)
      end

    end
  end
end