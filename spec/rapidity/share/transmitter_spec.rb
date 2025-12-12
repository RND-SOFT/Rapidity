require 'active_support/all'

RSpec.describe Rapidity::Share::Transmitter do
  let(:namespace){ "test_workplace" }
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end
  let(:generator){ Rapidity::Share::Generator.new(pool, namespace:) }
  subject(:transmitter){ described_class.new(pool, namespace:) }

  before(:each) do
    pool.with { |r| r.flushdb }
  end

  describe '#acquire' do
    context 'single limit' do
      let(:limit_name){ 'limit' }
      let(:limit_key){ transmitter.redis_key(limit_name) }
      
      before do
        generator.init(Rapidity::Share::Limit.new(limit_name, 1, 60))
      end

      it 'success' do
        response = transmitter.acquire([limit_key], tokens: 1)
        expect(response.success).to eq(true)
        
        info = generator.info(limit_key)
        expect(info.limit.tokens).to eq(0)
      end

      it 'failure' do
        # попросили больше чем есть
        response = transmitter.acquire([limit_key], tokens: 2)
        expect(response.success).to eq(false)
        
        info = generator.info(limit_key)
        expect(info.limit.tokens).to eq(1)

        # выбрали все что есть есть
        response = transmitter.acquire([limit_key], tokens: 1)
        response = transmitter.acquire([limit_key], tokens: 1)
        expect(response.success).to eq(false)
        
        info = generator.info(limit_key)
        expect(info.limit.tokens).to eq(0)
      end

      it 'zero' do
        response = transmitter.acquire([limit_key], tokens: 0)
        expect(response.success).to eq(false)
        
        info = generator.info(limit_key)
        expect(info.limit.tokens).to eq(1)
      end
    end

    context 'multiple limits' do
      before do
        generator.init(Rapidity::Share::Limit.new('limit_1', 1, 60))
        generator.init(Rapidity::Share::Limit.new('limit_2', 5, 30))
        generator.init(Rapidity::Share::Limit.new('limit_3', 2, 120))
      end

      let(:limit_keys) do
        ['limit_1', 'limit_2', 'limit_3'].map do |name|
          transmitter.redis_key(name)
        end
      end

      it 'success' do
        response = transmitter.acquire(limit_keys, tokens: 1)
        expect(response.success).to eq(true)

        expect(generator.info(limit_keys[0]).limit.tokens).to eq(0)
        expect(generator.info(limit_keys[1]).limit.tokens).to eq(4)
        expect(generator.info(limit_keys[2]).limit.tokens).to eq(1)
      end

      it 'failure' do
        # попросили больше чем есть
        response = transmitter.acquire(limit_keys, tokens: 2)
        expect(response.success).to eq(false)
        
        expect(generator.info(limit_keys[0]).limit.tokens).to eq(1)
        expect(generator.info(limit_keys[1]).limit.tokens).to eq(5)
        expect(generator.info(limit_keys[2]).limit.tokens).to eq(2)

        # выбрали все что есть есть
        response = transmitter.acquire(limit_keys, tokens: 1)
        response = transmitter.acquire(limit_keys, tokens: 1)
        expect(response.success).to eq(false)

        expect(generator.info(limit_keys[0]).limit.tokens).to eq(0)
        expect(generator.info(limit_keys[1]).limit.tokens).to eq(4)
        expect(generator.info(limit_keys[2]).limit.tokens).to eq(1)
      end

      it 'only requested' do
        response = transmitter.acquire([limit_keys[1], limit_keys[2]], tokens: 2)
        expect(response.success).to eq(true)
        
        expect(generator.info(limit_keys[0]).limit.tokens).to eq(1)
        expect(generator.info(limit_keys[1]).limit.tokens).to eq(3)
        expect(generator.info(limit_keys[2]).limit.tokens).to eq(0)
      end
    end

    context 'exceptions' do
      before do
        generator.init(Rapidity::Share::Limit.new('limit_1', 1, 60))
        generator.init(Rapidity::Share::Limit.new('limit_2', 5, 30))
        generator.init(Rapidity::Share::Limit.new('limit_3', 2, 120))
      end

      let(:limit_keys) do
        ['limit_1', 'limit_2', 'limit_3'].map do |name|
          transmitter.redis_key(name)
        end
      end
      
      it 'not exists' do
        non_existent_key = transmitter.send(:redis_key, 'non_existent')
        response = transmitter.acquire([non_existent_key], tokens: 1)
        expect(response.success).to eq(false)

        response = transmitter.acquire([*limit_keys, non_existent_key], tokens: 1)
        expect(response.success).to eq(false)
      end

      it 'no keys' do
        response = transmitter.acquire([], tokens: 10)
        expect(response.success).to eq(false)
      end

      it 'обрабатывает отрицательное количество токенов' do
        response = transmitter.acquire([limit_keys[0]], tokens: -5)
        expect(response.success).to eq(false)
      end
    end
  end
end