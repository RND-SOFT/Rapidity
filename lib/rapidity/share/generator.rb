module Rapidity
  module Share
    class Generator < Base
      
      LUA_SCRIPTS = [:init]
      
      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def init_limit(params, queue: nil)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_init, keys: [redis_key(limit.name)], argv: [limit.count, limit.interval, limit.queue_length, DEFAULT_KEY_TTL])
            end
          end
        end
      end

      def parse_limit(param)
        Limiter.new(*param.split(":"))
      end
    end
  end
end