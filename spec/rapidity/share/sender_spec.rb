require 'active_support/all'

RSpec.describe Rapidity::Share::Sender do
  let!(:namespace){ "test_workplace" }
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end
  let(:producer){ Rapidity::Share::Producer.new(pool) }
  subject(:sender){ described_class.new(pool) }

  before(:each) do
    pool.with { |r| r.flushdb }
  end

  describe '#acquire' do
    context 'single limit' do
      let!(:limit){Rapidity::Share::Limit.new('limit', 1, 60, namespace: namespace)}
      
      before do
        producer.init(limit)
      end

      it 'success' do
        response = sender.acquire([limit.name], tokens: 1)
        expect(response.success).to eq(true)
        
        info = producer.info(limit.name)
        expect(info.limit.tokens).to eq(0)
      end

      it 'failure' do
        # попросили больше чем есть
        response = sender.acquire([limit.name], tokens: 2)
        expect(response.success).to eq(false)
        
        info = producer.info(limit.name)
        expect(info.limit.tokens).to eq(1)

        # выбрали все что есть есть
        response = sender.acquire([limit.name], tokens: 1)
        response = sender.acquire([limit.name], tokens: 1)
        expect(response.success).to eq(false)
        
        info = producer.info(limit.name)
        expect(info.limit.tokens).to eq(0)
      end

      it 'zero' do
        expect{sender.acquire([limit.name], tokens: 0)}.to raise_error(ArgumentError)
        
        info = producer.info(limit.name)
        expect(info.limit.tokens).to eq(1)
      end
    end

    context 'multiple limits' do
      before do
        producer.init(Rapidity::Share::Limit.new('limit_1', 1, 60, namespace: namespace))
        producer.init(Rapidity::Share::Limit.new('limit_2', 5, 30, namespace: namespace))
        producer.init(Rapidity::Share::Limit.new('limit_3', 2, 120, namespace: namespace))
      end

      let(:limit_names) {['limit_1', 'limit_2', 'limit_3'].map{|it| [namespace, it].join(':')}}

      it 'success' do
        response = sender.acquire(limit_names, tokens: 1)
        expect(response.success).to eq(true)

        expect(producer.info(limit_names[0]).limit.tokens).to eq(0)
        expect(producer.info(limit_names[1]).limit.tokens).to eq(4)
        expect(producer.info(limit_names[2]).limit.tokens).to eq(1)
      end

      it 'failure' do
        # попросили больше чем есть
        response = sender.acquire(limit_names, tokens: 2)
        expect(response.success).to eq(false)
        
        expect(producer.info(limit_names[0]).limit.tokens).to eq(1)
        expect(producer.info(limit_names[1]).limit.tokens).to eq(5)
        expect(producer.info(limit_names[2]).limit.tokens).to eq(2)

        # выбрали все что есть есть
        response = sender.acquire(limit_names, tokens: 1)
        response = sender.acquire(limit_names, tokens: 1)
        expect(response.success).to eq(false)

        expect(producer.info(limit_names[0]).limit.tokens).to eq(0)
        expect(producer.info(limit_names[1]).limit.tokens).to eq(4)
        expect(producer.info(limit_names[2]).limit.tokens).to eq(1)
      end

      it 'only requested' do
        response = sender.acquire([limit_names[1], limit_names[2]], tokens: 2)
        expect(response.success).to eq(true)
        
        expect(producer.info(limit_names[0]).limit.tokens).to eq(1)
        expect(producer.info(limit_names[1]).limit.tokens).to eq(3)
        expect(producer.info(limit_names[2]).limit.tokens).to eq(0)
      end
    end

    context 'token restore' do
       let!(:limit){Rapidity::Share::Limit.new('limit', 10, 60, namespace: namespace)}
      
      before do
        producer.init(limit)
      end

      it 'not exceed max value' do
        future_time = Time.now.to_i + 65
        pool.with do |conn|
          conn.with do |r|
            r.hset(limit.name, 'last_used', future_time)
          end
        end
        
        response = sender.acquire([limit.name], tokens: 11)
        expect(response.success).to eq(false)

        expect(producer.info(limit.name).limit.tokens).to eq(10)
      end

      it 'restore after acquire' do
        response = sender.acquire([limit.name], tokens: 10)
        expect(response.success).to eq(true)
        
        old_time = Time.now.to_i - 65
        pool.with do |conn|
          conn.with do |r|
            r.hset(limit.name, 'last_used', old_time)
          end
        end
        
        response = sender.acquire([limit.name], tokens: 10)
        expect(response.success).to eq(true)
      end

      it 'update last_used only if success acquire' do
        initial_last_used = producer.info(limit.name).limit.last_used.to_i
        
        sleep(2)

        response = sender.acquire([limit.name], tokens: 11)
        expect(response.success).to eq(false)

        not_changed_last_used = producer.info(limit.name).limit.last_used.to_i
        expect(initial_last_used).to eq(not_changed_last_used)
        
        response = sender.acquire([limit.name], tokens: 5)
        expect(response.success).to eq(true)

        new_last_used = producer.info(limit.name).limit.last_used.to_i
        
        expect(new_last_used).to be > initial_last_used
      end
    end

    context 'retryable' do
      let!(:limit) { Rapidity::Share::Limit.new('limit', 1, 60, namespace: namespace) }

      before { producer.init(limit) }

      it 'distinguishes rate limit from configuration error' do
        sender.acquire([limit.name], tokens: 1)
        rate_limited = sender.acquire([limit.name], tokens: 1)
        expect(rate_limited.success).to eq(false)
        expect(rate_limited.retryable).to eq("true")

        not_found = sender.acquire(['key_not_exist'], tokens: 1)
        expect(not_found.success).to eq(false)
        expect(not_found.retryable).to eq("false")
      end
    end

    context 'exceptions' do
      before do
        producer.init(Rapidity::Share::Limit.new('limit_1', 1, 60, namespace: namespace))
        producer.init(Rapidity::Share::Limit.new('limit_2', 5, 30, namespace: namespace))
        producer.init(Rapidity::Share::Limit.new('limit_3', 2, 120, namespace: namespace))
      end

      let(:limit_names) { ['limit_1', 'limit_2', 'limit_3'].map{|it| [namespace, it].join(':')}}
      
      it 'not exists' do
        non_existent_key = 'key_not_exist'
        response = sender.acquire([non_existent_key], tokens: 1)
        expect(response.success).to eq(false)

        response = sender.acquire([*limit_names, non_existent_key], tokens: 1)
        expect(response.success).to eq(false)
      end

      it 'no keys' do
        expect { sender.acquire([], tokens: 10) }.to raise_error(ArgumentError, /empty/)
      end

      it 'negative tokens count' do
        expect { sender.acquire([limit_names[0]], tokens: -5) }.to raise_error(ArgumentError, /positive/)
      end

      it 'zero tokens count' do
        expect { sender.acquire([limit_names[0]], tokens: 0) }.to raise_error(ArgumentError, /positive/)
      end
    end
  end

  describe '#available_in' do
    context 'single limit' do
      let!(:limit){Rapidity::Share::Limit.new('limit', 10, 10, namespace: namespace)}
        
      before do
        producer.init(limit)
      end

      it 'available now' do
        response = sender.available_in([limit], tokens: 2)
        expect(response.success).to eq(true)
        expect(response.available_in).to eq(0)
      end

      it 'available in' do
        response = sender.acquire([limit], tokens: 10)
        expect(response.success).to eq(true)
        
        response = sender.available_in([limit], tokens: 10)
        expect(response.success).to eq(true)
        expect(response.available_in).to be > 9
      end

      it 'not exist' do
        response = sender.available_in(['key_not_exist'], tokens: 10)
        expect(response.success).to eq(false)
      end
    end

    context 'multiple limit' do
      before do
        producer.init(Rapidity::Share::Limit.new('limit_1', 10, 10, namespace: namespace))
        producer.init(Rapidity::Share::Limit.new('limit_2', 10, 10, namespace: namespace))
        producer.init(Rapidity::Share::Limit.new('limit_3', 10, 10, namespace: namespace))
      end

      let(:limit_names) { ['limit_1', 'limit_2', 'limit_3'].map{|it| [namespace, it].join(':')}}

      it 'available now' do
        response = sender.available_in([*limit_names], tokens: 2)
        expect(response.success).to eq(true)
        expect(response.available_in).to eq(0)
      end

      it 'available in' do
        response = sender.acquire([limit_names[2]], tokens: 5)
        expect(response.success).to eq(true)
        response = sender.acquire([limit_names[1]], tokens: 7)
        expect(response.success).to eq(true)
        response = sender.acquire([limit_names[0]], tokens: 10)
        expect(response.success).to eq(true)
        
        response = sender.available_in([*limit_names], tokens: 10)
        expect(response.success).to eq(true)
        expect(response.available_in).to be > 9
      end

      it 'not exist' do
        response = sender.available_in([*limit_names, 'key_not_exist'], tokens: 2)
        expect(response.success).to eq(false)
      end
    end
    
  end
  
  describe '#release_queue' do
    let!(:limit){Rapidity::Share::Limit.new('limit', 10, 60, max_queue: 10, namespace: namespace)}
      
    before do
      producer.init(limit)
    end

    it 'release' do
      response = producer.acquire_queue(limit, count: 2)
      expect(response.success).to eq(true)
      
      info = sender.info(limit)
      expect(info.limit.semaphore).to eq(8)

      response = sender.release_queue(limit, count: 2)
      expect(response.success).to eq(true)

      info = sender.info(limit)
      expect(info.limit.semaphore).to eq(10)
    end

    it 'release less then max' do
      info = sender.info(limit)
      expect(info.limit.semaphore).to eq(10)

      response = sender.release_queue(limit, count: 10)
      expect(response.success).to eq(true)

      info = sender.info(limit)
      expect(info.limit.semaphore).to eq(10)
    end
  end
end