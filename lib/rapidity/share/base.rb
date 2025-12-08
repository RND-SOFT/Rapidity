module Rapidity
  module Share
    class Base
      
      LUA_SCRIPTS = []
      DEFAULT_KEY_TTL = 3.days
      
      def initialize(pool,  ttl: DEFAULT_KEY_TTL.to_i, key_builder: nil, namespace: 'rapidity', **kwargs)
        @pool = pool
        @namespace = namespace
        @key_builder = method(:default_build_redis_key) if key_builder.nil?
      end

      private def wrap_executed_script(&block)
        yield block
      rescue ::Redis::CommandError => e
        if e.message.include?('NOSCRIPT')
          logger.warn("Get not script error from redis: #{e.message}. Reload lua scripts")
          # существует вероятность что сервер мог быть перезагружен
          # и нужно заново загрузить скрипты
          load_redis_scripts
          retry
        end
        raise e
      end

      private def load_redis_scripts
        @pool.with do |conn|
          LUA_SCRIPTS.each do |script|
            instance_variable_set("@lua_#{script}".to_sym,
              conn.with {|r| r.script(:load, File.read(File.join(__dir__, 'lua_scripts', script))) }
            )
          end
        end
      end

      protected def redis_key(key)
        @key_builder.call(key)
      end

      protected def default_build_redis_key(*key)
        [@namespace, *key].join(':')
      end

      def parse_limit(param)
        Limiter.new(*param.split(":"))
      end
      
    end
  end
end