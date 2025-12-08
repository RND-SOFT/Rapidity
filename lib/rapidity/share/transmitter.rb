module Rapidity
  module Share
    class Trasmitter
      
      LUA_SCRIPTS = [:check, :spend]
      
      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def check(limits)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_check, argv: [limits])
            end
          end
        end
      end

      def dec_queue(limits)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_dec_queue, argv: [limits])
            end
          end
        end
      end

      def inc_queue(limits)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_inc_queue, argv: [limits])
            end
          end
        end
      end

      def spend(limits)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_spend, argv: [limits])
            end
          end
        end
      end
    end
  end
end