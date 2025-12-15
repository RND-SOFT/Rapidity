module Rapidity
  module Share
    class Transmitter < Base

      LUA_SCRIPTS = [:acquire]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def acquire(list_limits_or_str, tokens: 1)
        limits = if list_limits_or_str[0].is_a?(Limit)
          list_limits_or_str.map {|it| redis_key(it.name)}
        else
          list_limits_or_str.map {|it| redis_key(it)}
        end

        response = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_acquire, keys: [*limits], argv: [tokens])
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

      def available_in(limit_or_str, tokens: 1)
        name = redis_key(limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_available_in, keys: [name], argv: [tokens])
            end
          end
        end
      end
    end
  end
end