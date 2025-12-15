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
      
      before do
        generator.init(Rapidity::Share::Limit.new(limit_name, 1, 60))
      end

      it 'success' do
        response = transmitter.acquire([limit_name], tokens: 1)
        expect(response.success).to eq(true)
        
        info = generator.info(limit_name)
        expect(info.limit.tokens).to eq(0)
      end

      it 'failure' do
        # попросили больше чем есть
        response = transmitter.acquire([limit_name], tokens: 2)
        expect(response.success).to eq(false)
        
        info = generator.info(limit_name)
        expect(info.limit.tokens).to eq(1)

        # выбрали все что есть есть
        response = transmitter.acquire([limit_name], tokens: 1)
        response = transmitter.acquire([limit_name], tokens: 1)
        expect(response.success).to eq(false)
        
        info = generator.info(limit_name)
        expect(info.limit.tokens).to eq(0)
      end

      it 'zero' do
        response = transmitter.acquire([limit_name], tokens: 0)
        expect(response.success).to eq(false)
        
        info = generator.info(limit_name)
        expect(info.limit.tokens).to eq(1)
      end
    end

    context 'multiple limits' do
      before do
        generator.init(Rapidity::Share::Limit.new('limit_1', 1, 60))
        generator.init(Rapidity::Share::Limit.new('limit_2', 5, 30))
        generator.init(Rapidity::Share::Limit.new('limit_3', 2, 120))
      end

      let(:limit_names) {['limit_1', 'limit_2', 'limit_3']}

      it 'success' do
        response = transmitter.acquire(limit_names, tokens: 1)
        expect(response.success).to eq(true)

        expect(generator.info(limit_names[0]).limit.tokens).to eq(0)
        expect(generator.info(limit_names[1]).limit.tokens).to eq(4)
        expect(generator.info(limit_names[2]).limit.tokens).to eq(1)
      end

      it 'failure' do
        # попросили больше чем есть
        response = transmitter.acquire(limit_names, tokens: 2)
        expect(response.success).to eq(false)
        
        expect(generator.info(limit_names[0]).limit.tokens).to eq(1)
        expect(generator.info(limit_names[1]).limit.tokens).to eq(5)
        expect(generator.info(limit_names[2]).limit.tokens).to eq(2)

        # выбрали все что есть есть
        response = transmitter.acquire(limit_names, tokens: 1)
        response = transmitter.acquire(limit_names, tokens: 1)
        expect(response.success).to eq(false)

        expect(generator.info(limit_names[0]).limit.tokens).to eq(0)
        expect(generator.info(limit_names[1]).limit.tokens).to eq(4)
        expect(generator.info(limit_names[2]).limit.tokens).to eq(1)
      end

      it 'only requested' do
        response = transmitter.acquire([limit_names[1], limit_names[2]], tokens: 2)
        expect(response.success).to eq(true)
        
        expect(generator.info(limit_names[0]).limit.tokens).to eq(1)
        expect(generator.info(limit_names[1]).limit.tokens).to eq(3)
        expect(generator.info(limit_names[2]).limit.tokens).to eq(0)
      end
    end

    context 'token restore' do
      let(:limit_name){ 'limit' }
      
      before do
        generator.init(Rapidity::Share::Limit.new(limit_name, 10, 60))
      end

      it 'not exceed max value' do
        future_time = Time.now.to_i + 65
        pool.with do |conn|
          conn.with do |r|
            r.hset(generator.redis_key(limit_name), 'last_used', future_time)
          end
        end
        
        response = transmitter.acquire([limit_name], tokens: 11)
        expect(response.success).to eq(false)

        expect(generator.info(limit_name).limit.tokens).to eq(10)
      end

      it 'restore after acquire' do
        response = transmitter.acquire([limit_name], tokens: 10)
        expect(response.success).to eq(true)
        
        old_time = Time.now.to_i - 65
        pool.with do |conn|
          conn.with do |r|
            r.hset(generator.redis_key(limit_name), 'last_used', old_time)
          end
        end
        
        response = transmitter.acquire([limit_name], tokens: 10)
        expect(response.success).to eq(true)
      end

      it 'update last_used only if success acquire' do
        initial_last_used = generator.info(limit_name).limit.last_used.to_i
        
        sleep(2)

        response = transmitter.acquire([limit_name], tokens: 11)
        expect(response.success).to eq(false)

        not_changed_last_used = generator.info(limit_name).limit.last_used.to_i
        expect(initial_last_used).to eq(not_changed_last_used)
        
        response = transmitter.acquire([limit_name], tokens: 5)
        expect(response.success).to eq(true)

        new_last_used = generator.info(limit_name).limit.last_used.to_i
        
        expect(new_last_used).to be > initial_last_used
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