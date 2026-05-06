require 'ostruct'

module Rapidity
  module Share
    class Base

      LUA_SCRIPTS = []
      BASE_SCRIPTS = [:list, :info, :reset, :delete]
      DEFAULT_KEY_TTL = 6000

      MX = Monitor.new

      def initialize(pool, ttl: DEFAULT_KEY_TTL.to_i, logger: nil)
        @pool = pool
        @ttl = ttl
        @logger = logger || Logger.new(STDOUT)
        @logger.level = Logger::DEBUG
        # load_redis_scripts
        restore_lua_hashes
      end

      # Returns a list of limits matching the pattern
      #
      # @param match_pattern [String] pattern for key matching
      # @param max_count [Integer] maximum number of records to return
      # @return [Array<Limit>] array of Limit objects or empty array
      def list(match_pattern, max_count: 1000)
        response = wrap_executed_script do |r|
          r.evalsha(@lua_list, argv: [match_pattern, max_count])
        end

        response = response.each_slice(2).to_h
        if response["count"].to_i > 0
          response["limits"].map do |data|
            build_limit(data)
          end
        else
          []
        end
      end

      # Resets limit values
      #
      # @param limit_or_str [Limit, String] limit object or its name
      # @param ttl [Integer] key TTL after reset
      # @return [OpenStruct] operation result with success and limit fields
      def reset(limit_or_str, ttl: @ttl)
        response = wrap_executed_script do |r|
          r.evalsha(@lua_reset, keys: [get_name(limit_or_str)], argv: [ttl])
        end

        handle_response(response, with_limit: true)
      end

      # Deletes a limit from Redis
      #
      # @param limit_or_str [Limit, String] limit object or its name
      # @return [OpenStruct] operation result with success field
      def delete(limit_or_str)
        response = wrap_executed_script do |r|
          r.evalsha(@lua_delete, keys: [get_name(limit_or_str)])
        end

        handle_response(response)
      end

      # Retrieves information about a limit
      #
      # @param limit_or_str [Limit, String] limit object or its name
      # @param ttl [Integer] key TTL
      # @return [OpenStruct] operation result with success and limit fields
      def info(limit_or_str, ttl: @ttl)
        response = wrap_executed_script do |r|
          r.evalsha(@lua_info, keys: [get_name(limit_or_str)], argv: [ttl])
        end

        handle_response(response, with_limit: true)
      end

      # Processes Redis response and converts it to OpenStruct
      #
      # @param response [Array] raw Redis response
      # @param with_limit [Boolean] whether to include limit object in result
      # @return [OpenStruct] structured response
      def handle_response(response, with_limit: false)
        response = response.each_slice(2).to_h
        success = response["result"] == "true"
        result_data = { success: success, **response }
        result_data[:limit] = build_limit(response["info"]) if success && with_limit
        OpenStruct.new(result_data)
      end

      def get_name(limit_or_str)
        limit_or_str.is_a?(Limit) ? limit_or_str.name : limit_or_str
      end

      def build_limit(redis_data)
        name = redis_data[0]
        params = redis_data[1].each_slice(2).to_h
        Limit.from_hash(name, **params.symbolize_keys)
      end

      # Wrapper for Redis script execution with retry logic
      #
      # @param max_retries [Integer] maximum number of retry attempts
      # @param delay [Float] delay between retries in seconds
      # @param block [Proc] block containing Redis operations
      # @return [Array] Redis response or error response
      def wrap_executed_script(max_retries: 5, delay: 0.1, &block)
        retries_count = 0
        begin
          @pool.with do |conn|
            conn.with do |r|
              yield r
            end
          end
        rescue Redis::CannotConnectError, Redis::TimeoutError, Errno::ECONNREFUSED => e
          retries_count += 1
          if retries_count < max_retries
            @logger.warn("Redis connection error: #{e.message}.")
            sleep(delay)
            retry
          else
            @logger.error("Redis is not available: #{e.message}")
            raise e
          end
        rescue ::Redis::CommandError => e
          if e.message.include?('NOSCRIPT')
            retries_count += 1
            if retries_count < max_retries
              @logger.warn("Get not script error from redis: #{e.message}. Reload lua scripts")
              # существует вероятность что сервер мог быть перезагружен
              # и нужно заново загрузить скрипты
              load_redis_scripts
              retry
            end
          end
          raise e
        rescue TypeError => e
          if e.message.include?('Unsupported command argument type: NilClass')
            retries_count += 1
            if retries_count < max_retries
              @logger.info("First time load lua scripts")
              # При первом запуске instance_variable с lua скриптами не инициализированы, при этом
              # evalsha райзит эту ошибку. Загружаем скрипты в redis
              load_redis_scripts
              retry
            end
          end
          raise e
        end
      end

      private

      # Loads Lua scripts into Redis
      #
      # @return [void]
      def load_redis_scripts
        cls = self.class
        MX.synchronize do 
          @pool.with do |conn|
            list_lua_scripts.each do |script|
              cls.instance_variable_set(lua_script_var(script),
                conn.with {|r| r.script(:load, File.read(File.join(__dir__, 'lua_scripts', "#{script.to_s}.lua"))) }
              )
            end
          end
        end
        restore_lua_hashes
      end

      # Restore instance script hashes from class cache
      def restore_lua_hashes
        cls = self.class
        list_lua_scripts.each do |script|
          instance_variable_set(lua_script_var(script), cls.instance_variable_get(lua_script_var(script)))
        end
      end


      # это для тестов чтобы проверить перезугрузку сриптов
      def reset_lua_scripts
        cls = self.class
        list_lua_scripts.each do |script|
          instance_variable_set(lua_script_var(script), nil)
        end
      end

      def list_lua_scripts
        (BASE_SCRIPTS + self.class::LUA_SCRIPTS)
      end

      def lua_script_var(script)
        "@lua_#{script}".to_sym
      end


    end
  end
end