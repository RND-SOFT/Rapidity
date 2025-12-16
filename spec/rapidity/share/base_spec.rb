require 'active_support/all'

RSpec.describe Rapidity::Share::Base do
  let(:namespace){ "test_workplace" }
  subject(:base){ described_class.new(pool) }
  subject(:generator){ Rapidity::Share::Generator.new(pool) }
  
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end

  before(:each) do
    pool.with { |r| r.flushdb }
  end

  context "#noscript" do
    it 'reload scripts' do
      limit = Rapidity::Share::Limit.new('limit_1', 20, 100, namespace:)
      generator.init(limit)
      result = base.info(limit)
      expect(result.success).to eq(true)
      
      pool.with do |conn|
        conn.with do |r|
          r.script(:flush, 'SYNC')
        end
      end

      result = base.info(limit)
      expect(result.success).to eq(true)
    end
  end
end