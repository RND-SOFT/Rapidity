require 'redis'

module Rapidity
  autoload :VERSION, 'rapidity/version'
  autoload :Limiter, 'rapidity/limiter'
  autoload :Composer, 'rapidity/composer'
  
  module Share
    autoload :Base, 'rapidity/share/base'
    autoload :Producer, 'rapidity/share/producer'
    autoload :Sender, 'rapidity/share/sender'
    autoload :Limit, 'rapidity/share/limit'
  end
end

