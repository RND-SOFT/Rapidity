module Rapidity
  module Share
    class Transmitter < Base

      LUA_SCRIPTS = [:acquire, :release_queue, :available_in]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def acquire(list_limits_or_str, tokens: 1, ttl: @ttl)
        limits = if list_limits_or_str[0].is_a?(Limit)
          list_limits_or_str.map {|it| it.name}
        else
          list_limits_or_str
        end

        response = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_acquire, keys: [*limits], argv: [tokens, ttl])
            end
          end
        end

        response = response.each_slice(2).to_h
        success = response["result"] == "true"
        OpenStruct.new(
          success: success,
          **response
        )
      end

      def release_queue(limit_or_str, count: 1, ttl: @ttl)
        name = limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str
        response = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_release_queue, keys: [name], argv: [count, ttl])
            end
          end
        end

        response = response.each_slice(2).to_h
        success = response["result"] == "true"
        OpenStruct.new(
          success: success,
          **response
        )
      end

      def available_in(list_limits_or_str, tokens: 1, ttl: @ttl)
        limits = if list_limits_or_str[0].is_a?(Limit)
          list_limits_or_str.map {|it| it.name}
        else
          list_limits_or_str
        end
        
        response = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_available_in, keys: [*limits], argv: [tokens, ttl])
            end
          end
        end
        
        response = response.each_slice(2).to_h
        success = response["result"] == "true"
        OpenStruct.new(
          success: success,
          **response
        )
      end
    end
  end
end