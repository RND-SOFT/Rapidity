require 'active_support/all'

RSpec.describe Rapidity::Share::Base do
  let(:namespace){ "test_workplace" }
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end
  let(:producer){ Rapidity::Share::Producer.new(pool) }
  subject(:base){ described_class.new(pool) }

  before(:each) do
    pool.with { |r| r.flushdb }
  end

  context "#noscript" do
    it 'reload scripts' do
      limit = Rapidity::Share::Limit.new('limit_1', 20, 100, namespace: namespace)
      producer.init(limit)
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

    it 'reload scripts not not exceed max attempts' do
      limit = Rapidity::Share::Limit.new('limit_1', 20, 100, namespace: namespace)
      producer.init(limit)
      result = base.info(limit)
      expect(result.success).to eq(true)

      expect do
        base.wrap_executed_script do |r|
          pool.with do |conn|
            conn.with do |r|
              r.script(:flush, 'SYNC')
              r.evalsha(base.instance_variable_get('@lua_info'), keys: ['42'])
            end
          end
        end
      end.to raise_error
    end
  end
end