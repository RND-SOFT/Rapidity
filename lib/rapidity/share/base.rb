module Rapidity
  module Share
    class Base

      LUA_SCRIPTS = []
      BASE_SCRIPTS = [:list, :info, :reset, :delete]
      DEFAULT_KEY_TTL = 3.days

      def initialize(pool, ttl: DEFAULT_KEY_TTL.to_i, key_builder: nil, namespace: 'rapidity', **kwargs)
        @pool = pool
        @ttl = ttl
        @key_builder = method(:default_build_redis_key) if key_builder.nil?
        @namespace = namespace
      end

      def list(pattern)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_list, argv: [pattern])
            end
          end
        end
      end

      def reset(name)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_reset, argv: [name])
            end
          end
        end
      end

      def delete(name)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_delete, argv: [name])
            end
          end
        end
      end

      def info(name)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_info, argv: [name])
            end
          end
        end
      end

      private 

      def wrap_executed_script(&block)
        max_retries = 3
        retries_count = 0

        yield block
      rescue  Redis::CannotConnectError, Redis::TimeoutError, Errno::ECONNREFUSED => e
        retries_count += 1 
        if retries_count >= max_retries
          logger.error("Redis is not available: #{e.message}")
          nil
        else
          retry
        end
      rescue ::Redis::CommandError => e
        if e.message.include?('NOSCRIPT')
          retries_count += 1
          if retries_count >= max_retries
            logger.warn("Get not script error from redis: #{e.message}. Reload lua scripts")
            # существует вероятность что сервер мог быть перезагружен
            # и нужно заново загрузить скрипты
            load_redis_scripts
            retry
          end
        end
        raise e
      end

      def load_redis_scripts
        @pool.with do |conn|
          (BASE_SCRIPTS + LUA_SCRIPTS).each do |script|
            instance_variable_set("@lua_#{script}".to_sym,
              conn.with {|r| r.script(:load, File.read(File.join(__dir__, 'lua_scripts', script))) }
            )
          end
        end
      end

      def redis_key(key)
        @key_builder.call(key)
      end

      def default_build_redis_key(*key)
        [@namespace, *key].join(':')
      end

      def parse_limit(param)
        Limiter.new(*param.split(":"))
      end

    end
  end
end