module Rapidity
  module Share
    class Transmitter < Base

      LUA_SCRIPTS = [:acquire]

      def initialize(*args, **kwargs)
        super(*args, **kwargs)
      end

      def acquire(limits, tokens: 1)
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