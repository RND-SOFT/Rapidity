require 'connection_pool'
require 'redis'

module Rapidity
  class Limiter

    attr_reader :pool, :name, :interval, :threshold, :namespace

    LUA_SCRIPT_CODE = File.read(File.join(__dir__, 'limiter.lua'))

    # Convert message to given class
    # @params pool - inititalized Redis pool
    # @params name - limiter name - part of the Redis key name
    # @params interval - interval in seconds to apply this limit
    # @params threshold - maximum available events for this interval
    # @params namespace - namespace for Redis keys
    def initialize(pool, name:, interval: 10, threshold: 10, namespace: 'rapidity')
      @pool = pool
      @interval = interval
      @threshold = threshold
      @name = name

      @namespace = namespace
    end

    def key(path)
      "#{namespace}:#{name}_#{path}"
    end

    # Get current counter
    # @return remaining counter value
    def remains
      results = @pool.with do |conn|
        conn.multi do |pipeline|
          pipeline.set(key('remains'), threshold, ex: interval, nx: true)
          pipeline.get(key('remains'))
        end
      end
      results[1].to_i #=> pipeline.get(key('remains'))
    end

    # Obtain values from counter
    # @return count succesfuly obtained send slots
    def obtain(count = 5)
      count = count.abs

      result = begin
        @pool.with do |conn|
          conn.evalsha(@script, keys: [key('remains')], argv: [threshold, interval, count])
        end
      rescue Redis::CommandError => e
        if e.message.include?('NOSCRIPT')
          # The Redis server has never seen this script before. Needs to run only once in the entire lifetime
          # of the Redis server, until the script changes - in which case it will be loaded under a different SHA
          ensure_script_loaded
          retry
        else
          raise e
        end
      end

      taken = result.to_i

      if taken == 0
        ttl = @pool.with do |conn|
          conn.ttl(key('remains'))
        end

        # UNKNOWN BUG? reset if no ttl present. Many years ago once upon time we meet our key without TTL
        if ttl == -1
          STDERR.puts "ERROR[#{Time.now}]: TTL for key #{key('remains').inspect} disappeared!"
          @pool.with {|c| c.expire(key('remains'), interval) }
        end
      end

      taken
    end

    def ensure_script_loaded
      @script = @pool.with do |conn|
        conn.script(:load, LUA_SCRIPT_CODE)
      end
    end

  end
end

