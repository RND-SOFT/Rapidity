RSpec.configure do |config|
  config.before(:suite) do
    $logger = Logger.new(STDOUT).tap do |logger|
      logger.progname = "rspec"
      logger.level = "FATAL"
    end
  end
end