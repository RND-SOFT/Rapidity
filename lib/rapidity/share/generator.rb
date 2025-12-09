module Rapidity
  module Share
    class Generator < Base

      LUA_SCRIPTS = [:init, :check_queue]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def init(params)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              params.each do |param|
                limit = parse_limit(param)
                r.evalsha(@lua_init,
                  keys: [redis_key(limit.name)], 
                  argv: [
                    limit.count,
                    limit.interval,
                    limit.queue,
                    @ttl
                  ])
              end
            end
          end
        end
      end

      def update(params)
        init(params)
      end
      
      def check_queue(name)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_check_queue, keys: [name])
            end
          end
        end
      end

      def acquire_queue(name, count: 1)
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