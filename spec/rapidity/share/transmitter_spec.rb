require 'active_support/all'

RSpec.describe Rapidity::Share::Transmitter do
  let!(:namespace){ "test_workplace" }
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end
  let(:generator){ Rapidity::Share::Generator.new(pool) }
  subject(:transmitter){ described_class.new(pool) }

  before(:each) do
    pool.with { |r| r.flushdb }
  end

  describe '#acquire' do
    context 'single limit' do
      let!(:limit){Rapidity::Share::Limit.new('limit', 1, 60, namespace: namespace)}
      
      before do
        generator.init(limit)
      end

      it 'success' do
        response = transmitter.acquire([limit.name], tokens: 1)
        expect(response.success).to eq(true)
        
        info = generator.info(limit.name)
        expect(info.limit.tokens).to eq(0)
      end

      it 'failure' do
        # попросили больше чем есть
        response = transmitter.acquire([limit.name], tokens: 2)
        expect(response.success).to eq(false)
        
        info = generator.info(limit.name)
        expect(info.limit.tokens).to eq(1)

        # выбрали все что есть есть
        response = transmitter.acquire([limit.name], tokens: 1)
        response = transmitter.acquire([limit.name], tokens: 1)
        expect(response.success).to eq(false)
        
        info = generator.info(limit.name)
        expect(info.limit.tokens).to eq(0)
      end

      it 'zero' do
        response = transmitter.acquire([limit.name], tokens: 0)
        expect(response.success).to eq(false)
        
        info = generator.info(limit.name)
        expect(info.limit.tokens).to eq(1)
      end
    end

    context 'multiple limits' do
      before do
        generator.init(Rapidity::Share::Limit.new('limit_1', 1, 60, namespace: namespace))
        generator.init(Rapidity::Share::Limit.new('limit_2', 5, 30, namespace: namespace))
        generator.init(Rapidity::Share::Limit.new('limit_3', 2, 120, namespace: namespace))
      end

      let(:limit_names) {['limit_1', 'limit_2', 'limit_3'].map{|it| [namespace, it].join(':')}}

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
       let!(:limit){Rapidity::Share::Limit.new('limit', 10, 60, namespace: namespace)}
      
      before do
        generator.init(limit)
      end

      it 'not exceed max value' do
        future_time = Time.now.to_i + 65
        pool.with do |conn|
          conn.with do |r|
            r.hset(limit.name, 'last_used', future_time)
          end
        end
        
        response = transmitter.acquire([limit.name], tokens: 11)
        expect(response.success).to eq(false)

        expect(generator.info(limit.name).limit.tokens).to eq(10)
      end

      it 'restore after acquire' do
        response = transmitter.acquire([limit.name], tokens: 10)
        expect(response.success).to eq(true)
        
        old_time = Time.now.to_i - 65
        pool.with do |conn|
          conn.with do |r|
            r.hset(limit.name, 'last_used', old_time)
          end
        end
        
        response = transmitter.acquire([limit.name], tokens: 10)
        expect(response.success).to eq(true)
      end

      it 'update last_used only if success acquire' do
        initial_last_used = generator.info(limit.name).limit.last_used.to_i
        
        sleep(2)

        response = transmitter.acquire([limit.name], tokens: 11)
        expect(response.success).to eq(false)

        not_changed_last_used = generator.info(limit.name).limit.last_used.to_i
        expect(initial_last_used).to eq(not_changed_last_used)
        
        response = transmitter.acquire([limit.name], tokens: 5)
        expect(response.success).to eq(true)

        new_last_used = generator.info(limit.name).limit.last_used.to_i
        
        expect(new_last_used).to be > initial_last_used
      end
    end

    context 'exceptions' do
      before do
        generator.init(Rapidity::Share::Limit.new('limit_1', 1, 60, namespace: namespace))
        generator.init(Rapidity::Share::Limit.new('limit_2', 5, 30, namespace: namespace))
        generator.init(Rapidity::Share::Limit.new('limit_3', 2, 120, namespace: namespace))
      end

      let(:limit_names) { ['limit_1', 'limit_2', 'limit_3'].map{|it| [namespace, it].join(':')}}
      
      it 'not exists' do
        non_existent_key = 'key_not_exist'
        response = transmitter.acquire([non_existent_key], tokens: 1)
        expect(response.success).to eq(false)

        response = transmitter.acquire([*limit_names, non_existent_key], tokens: 1)
        expect(response.success).to eq(false)
      end

      it 'no keys' do
        response = transmitter.acquire([], tokens: 10)
        expect(response.success).to eq(false)
      end

      it 'negative tokens count' do
        response = transmitter.acquire([limit_names[0]], tokens: -5)
        expect(response.success).to eq(false)
      end
    end
  end

  describe '#available_in' do
    context 'single limit' do
      let!(:limit){Rapidity::Share::Limit.new('limit', 10, 10, namespace: namespace)}
        
      before do
        generator.init(limit)
      end

      it 'available now' do
        response = transmitter.available_in([limit], tokens: 2)
        expect(response.success).to eq(true)
        expect(response.available_in).to eq(0)
      end

      it 'available in' do
        response = transmitter.acquire([limit], tokens: 10)
        expect(response.success).to eq(true)
        
        response = transmitter.available_in([limit], tokens: 10)
        expect(response.success).to eq(true)
        expect(response.available_in).to be > 9
      end

      it 'not exist' do
        response = transmitter.available_in(['key_not_exist'], tokens: 10)
        expect(response.success).to eq(false)
      end
    end

    context 'multiple limit' do
      before do
        generator.init(Rapidity::Share::Limit.new('limit_1', 10, 10, namespace: namespace))
        generator.init(Rapidity::Share::Limit.new('limit_2', 10, 10, namespace: namespace))
        generator.init(Rapidity::Share::Limit.new('limit_3', 10, 10, namespace: namespace))
      end

      let(:limit_names) { ['limit_1', 'limit_2', 'limit_3'].map{|it| [namespace, it].join(':')}}

      it 'available now' do
        response = transmitter.available_in([*limit_names], tokens: 2)
        expect(response.success).to eq(true)
        expect(response.available_in).to eq(0)
      end

      it 'available in' do
        response = transmitter.acquire([limit_names[2]], tokens: 5)
        expect(response.success).to eq(true)
        response = transmitter.acquire([limit_names[1]], tokens: 7)
        expect(response.success).to eq(true)
        response = transmitter.acquire([limit_names[0]], tokens: 10)
        expect(response.success).to eq(true)
        
        response = transmitter.available_in([*limit_names], tokens: 10)
        expect(response.success).to eq(true)
        expect(response.available_in).to be > 9
      end

      it 'not exist' do
        response = transmitter.available_in([*limit_names, 'key_not_exist'], tokens: 2)
        expect(response.success).to eq(false)
      end
    end
    
  end
  
  describe '#release_queue' do
    let!(:limit){Rapidity::Share::Limit.new('limit', 10, 60, max_queue: 10, namespace: namespace)}
      
    before do
      generator.init(limit)
    end

    it 'release' do
      response = generator.acquire_queue(limit, count: 2)
      expect(response.success).to eq(true)
      
      info = transmitter.info(limit)
      expect(info.limit.queue).to eq(8)

      response = transmitter.release_queue(limit, count: 2)
      expect(response.success).to eq(true)

      info = transmitter.info(limit)
      expect(info.limit.queue).to eq(10)
    end

    it 'release less then max' do
      info = transmitter.info(limit)
      expect(info.limit.queue).to eq(10)

      response = transmitter.release_queue(limit, count: 10)
      expect(response.success).to eq(true)

      info = transmitter.info(limit)
      expect(info.limit.queue).to eq(10)
    end
  end
end