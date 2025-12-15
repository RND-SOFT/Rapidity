module Rapidity
  module Share
    class Base

      LUA_SCRIPTS = []
      BASE_SCRIPTS = [:list, :info, :reset, :delete]
      DEFAULT_KEY_TTL = 6000

      def initialize(pool, ttl: DEFAULT_KEY_TTL.to_i, key_builder: nil, namespace: nil, **kwargs)
        @pool = pool
        @ttl = ttl
        @key_builder = method(:default_build_redis_key) if key_builder.nil?
        @namespace = namespace
        load_redis_scripts
      end

      def list(match_pattern, max_count: 1000)
        response = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              response = r.evalsha(@lua_list, argv: [match_pattern, max_count])
              response = response.each_slice(2).to_h
            end
          end
        end

        if response["count"] > 0
          response["limits"].each do |data|
            build_limit(data)
          end
        else
          []
        end
      end

      def reset(limit_or_str)
        name = redis_key(limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_reset, keys: [name])
            end
          end
        end
      end

      def delete(limit_or_str)
        name = redis_key(limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str)
        wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_delete, keys: [name])
            end
          end
        end
      end

      def info(limit_or_str)
        name = redis_key(limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str)
        response = wrap_executed_script do
          @pool.with do |conn|
            conn.with do |r|
              r.evalsha(@lua_info, keys: [name])
            end
          end
        end

        response = response.each_slice(2).to_h
        if response["result"] == "true"
          limit = build_limit(response["info"])
          OpenStruct.new(
            success: true,
            limit: limit
          )
        else
          OpenStruct.new(
            success: false,
            **response
          )
        end
      end

      def redis_key(key)
        if @namespace
          @key_builder.call(key)
        else
          key
        end
      end

      def default_build_redis_key(*key)
        [@namespace, *key].join(':')
      end

      def extract_limit_name(redis_key)
        redis_key.split(':').last
      end

      def parse_limit(param)
        Limiter.new(*param.split(":"))
      end

      def build_limit(redis_data)
        name = extract_limit_name(redis_data[0])
        params = redis_data[1].each_slice(2).to_h
        Limit.from_hash(name, **params.symbolize_keys)
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
          (BASE_SCRIPTS + self.class::LUA_SCRIPTS).each do |script|
            instance_variable_set("@lua_#{script}".to_sym,
              conn.with {|r| r.script(:load, File.read(File.join(__dir__, 'lua_scripts', "#{script.to_s}.lua"))) }
            )
          end
        end
      end

    end
  end
end