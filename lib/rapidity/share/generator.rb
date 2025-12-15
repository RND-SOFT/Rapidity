module Rapidity
  module Share
    class Generator < Base

      LUA_SCRIPTS = [:init, :check_queue]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def init(limit)
        data = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_init,
                keys: [redis_key(limit.name)], 
                argv: [*limit.base_params, @ttl])
            end
          end
        end

        limit = build_limit(data)
        limit.valid? & limit.persisted?
      end

      def update(params)
        init(params)
      end

      def check_queue(limit_or_str)
        name = redis_key(limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_check_queue, keys: [name])
            end
          end
        end
      end

      def acquire_queue(limit_or_str, count: 1)
        name = redis_key(limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_check_queue, keys: [name], args: [count])
            end
          end
        end
      end

    end
  end
end