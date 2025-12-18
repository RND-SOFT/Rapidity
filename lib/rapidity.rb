require 'redis'

module Rapidity
  autoload :VERSION, 'rapidity/version'
  autoload :Limiter, 'rapidity/limiter'
  autoload :Composer, 'rapidity/composer'
  
  module Share
    autoload :Base, 'rapidity/share/base'
    autoload :Generator, 'rapidity/share/generator'
    autoload :Transmitter, 'rapidity/share/transmitter'
    autoload :Limit, 'rapidity/share/misc'
  end
end

