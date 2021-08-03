
require 'ostruct'

require_relative './limiter'


module Rapidity
  class Composer

    attr_reader :limits, :limiters, :name, :namespace

    # Combine multiple limits 
    # @params pool - inititalized Redis pool
    # @params name - limiter name - part of the Redis key name
    # @params limits - multiple limits definition

    ## limits example
    # ```ruby`
    #limits = [
    #  { threshold: 2, interval: 1 },   # 2 events per second
    #  { threshold: 9, interval: 5 },   # 9 events per 5 seconds
    #  { threshold: 20, interval: 20 }, # 20 events per 20 seconds
    #  { threshold: 42, interval: 60 }, # 42 events per 60 seconds
    #]
    #```

    # @params namespace - namespace for Redis keys
    def initialize pool, name:, limits: [], namespace: 'rapidity'
      @limits = limits
      @name = name
      @namespace = namespace
      
      @limiters = @limits.map.each_with_index do |l, i|
        limit = OpenStruct.new(l)
        ::Rapidity::Limiter.new(pool, name: "#{i}_#{name}_#{limit.limit}/#{limit.interval}", interval: limit.interval, threshold: limit.threshold, namespace: namespace)
      end
    end

    def remains
      @limiters.each_with_object({}) do |limiter, result|
        result[limiter.name] = limiter.remains
      end
    end

    def obtain(count = 5)
      @limiters.each do |limiter|
        count = limiter.obtain(count)
        break if count == 0
      end

      return count
    end

  end
end