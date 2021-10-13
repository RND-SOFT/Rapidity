require 'connection_pool'
require 'redis'

module Rapidity
  class Limiter

    attr_reader :pool, :name, :interval, :threshold, :namespace


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
      result = @pool.with do |conn|
        conn.multi do
          conn.set(key('remains'), threshold, ex: interval, nx: true)
          conn.get(key('remains'))
        end[1] #=> conn.get(key('remains'))
      end
      result.to_i
    end

    # Obtain values from counter
    # @return count succesfuly obtained send slots
    def obtain(count = 5)
      count = count.abs

      taken = @pool.with do |conn|
        conn.multi do
          conn.set(key('remains'), threshold, ex: interval, nx: true)
          conn.decrby(key('remains'), count)
        end[1] #=> conn.decrby(key('remains'), count)
      end

      if taken < 0
        overflow = taken.abs
        to_return = [count, overflow].min

        ttl = @pool.with do |conn|
          conn.multi do
            conn.set(key('remains'), threshold - to_return, ex: interval, nx: true)
            conn.incrby(key('remains'), to_return)
            conn.ttl(key('remains'))
          end[2] #=> conn.ttl(key('remains'))
        end

        @pool.with {|c| c.expire(key('remains'), interval) } if ttl == -1 # reset if no ttl present

        count - to_return
      else
        count
      end
    end

  end
end

