module Rapidity
  module Share
    class Generator < Base

      LUA_SCRIPTS = [:init, :check_queue, :acquire_queue]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def init(limit, ttl: @ttl)
        data = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_init,
                keys: [limit.name], 
                argv: [*limit.base_params, ttl])
            end
          end
        end

        limit = build_limit(data)
        limit.valid? & limit.persisted?
      end

      def update(*, **)
        init(*, **)
      end

      def check_queue(limit_or_str, ttl: @ttl)
        name = limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str
        response = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_check_queue, keys: [name, ttl])
            end
          end
        end

        response = response.each_slice(2).to_h
        if response["result"] == "true"
          OpenStruct.new(
            success: true,
            **response
          )
        else
          OpenStruct.new(
            success: false,
            **response
          )
        end
      end

      def acquire_queue(limit_or_str, count: 1, ttl: @ttl)
        name = limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str
        response = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_acquire_queue, keys: [name], argv: [count, ttl])
            end
          end
        end
        response = response.each_slice(2).to_h
        if response["result"] == "true"
          OpenStruct.new(
            success: true,
            **response
          )
        else
          OpenStruct.new(
            success: false,
            **response
          )
        end
      end

    end
  end
end