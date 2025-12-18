module Rapidity
  module Share
    class Transmitter < Base

      LUA_SCRIPTS = [:acquire, :release_queue, :available_in]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      # Attempts to acquire tokens from one or multiple rate limits
      #
      # This method attempts to reserve the specified number of tokens from each
      # limit in the provided list. The operation succeeds only if all limits
      # have available tokens.
      #
      # @param list_limits_or_str [Array<Limit>, Array<String>] array of limit objects or limit names
      # @param tokens [Integer] number of tokens to acquire from each limit
      # @param ttl [Integer] time-to-live for the acquisition operation
      # @return [OpenStruct] result of the acquisition attempt
      # @note If any limit cannot provide the requested tokens, the entire operation fails
      def acquire(list_limits_or_str, tokens: 1, ttl: @ttl)
        limits = if list_limits_or_str[0].is_a?(Limit)
          list_limits_or_str.map {|it| it.name}
        else
          list_limits_or_str
        end

        response = wrap_executed_script do |r|
          r.evalsha(@lua_acquire, keys: [*limits], argv: [tokens, ttl])
        end

        handle_response(response)
      end

      # Checks when tokens will be available in one or multiple rate limits
      #
      # Calculates the maximum time until the specified number of tokens will be
      # available across all provided limits.
      #
      # @param list_limits_or_str [Array<Limit>, Array<String>] array of limit objects or limit names
      # @param tokens [Integer] number of tokens to check availability for
      # @param ttl [Integer] time-to-live parameter for the check
      # @return [OpenStruct] availability information including wait times
      # @note Returns the maximum wait time among all limits (bottleneck)
      def available_in(list_limits_or_str, tokens: 1, ttl: @ttl)
        limits = if list_limits_or_str[0].is_a?(Limit)
          list_limits_or_str.map {|it| it.name}
        else
          list_limits_or_str
        end

        response = wrap_executed_script do |r|
          r.evalsha(@lua_available_in, keys: [*limits], argv: [tokens, ttl])
        end

        handle_response(response)
      end

      # Releases tokens back to the limit queue
      #
      # Returns previously acquired tokens to the queue, making them available
      # for generetor.
      #
      # @param limit_or_str [Limit, String] limit object or its name
      # @param count [Integer] number of tokens to release
      # @param ttl [Integer] time-to-live for the released tokens
      # @return [OpenStruct] result of the release operation
      def release_queue(limit_or_str, count: 1, ttl: @ttl)
        response = wrap_executed_script do |r|
          r.evalsha(@lua_release_queue, keys: [get_name(limit_or_str)], argv: [count, ttl])
        end

        handle_response(response)
      end
    end
  end
end