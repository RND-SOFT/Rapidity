# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rapidity/version'

Gem::Specification.new do |spec|
  spec.name          = 'rapidity'
  spec.version       = ENV['BUILDVERSION'].to_i > 0 ? "#{Rapidity::VERSION}.#{ENV['BUILDVERSION'].to_i}" : Rapidity::VERSION
  spec.authors       = ['Yurusov Vlad', 'Samoilenko Yuri']
  spec.email         = ['vyurusov@rnds.pro', 'kinnalru@gmail.com']

  spec.summary       = 'Simple distributed Redis-backed rate limiter'
  spec.description   = 'Simple distributed Redis-backed rate limiter'
  spec.required_ruby_version = '>= 2.5.0'

  spec.files         = Dir['bin/*', 'lib/**/*', 'Gemfile*', 'LICENSE', 'README.md']
  spec.bindir        = 'bin'
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'activesupport'
  spec.add_runtime_dependency 'connection_pool'
  spec.add_runtime_dependency 'redis'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'timeouter'

  spec.add_development_dependency 'awesome_print'
  spec.add_development_dependency 'bump'
  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'rspec-collection_matchers'
  spec.add_development_dependency 'rspec_junit_formatter'
  spec.add_development_dependency 'rubycritic'
  spec.add_development_dependency 'shoulda-matchers'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'simplecov-console'
end

