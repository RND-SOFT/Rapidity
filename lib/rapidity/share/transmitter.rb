module Rapidity
  module Share
    class Trasmitter < Base

      LUA_SCRIPTS = [:acquire, :available_in, :try_acquire_with_retry]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def acquire(limits, tokens: 1)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_acquire, keys: [*limits], argv: [tokens])
            end
          end
        end
      end

      def available_in(name, tokens: 1)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_available_in, argv: [limits])
            end
          end
        end
      end
    end
  end
end