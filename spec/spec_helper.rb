require 'bundler/setup'
ENV['RAILS_ENV'] ||= 'test'

if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov-console'
  require 'simplecov-cobertura'

  SimpleCov.start do
    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
                                                                 SimpleCov::Formatter::HTMLFormatter, # for gitlab
                                                                 SimpleCov::Formatter::Console, # for developers
                                                                 SimpleCov::Formatter::CoberturaFormatter
                                                               ])
    add_filter '/spec/'
    track_files 'lib/**/*.rb'
  end
end

require 'rapidity'
require 'securerandom'
require 'shoulda-matchers'

Bundler.require(:default, :development, :test)

$root = File.join(File.dirname(__dir__), 'spec')

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each {|f| require f }
Dir[File.join(__dir__, '**', 'shared', '**', '*.rb')].sort.each {|f| require f }

