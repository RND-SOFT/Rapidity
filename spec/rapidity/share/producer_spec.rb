require 'active_support/all'

RSpec.describe Rapidity::Share::Producer do
  let(:namespace){ "test_workplace" }
  subject(:producer){ described_class.new(pool) }
  let(:count){ 20 }
  let(:name){ "limit" }
  let(:interval){ 600 }
  let(:semaphore){ 20 }
  let(:limit) { Rapidity::Share::Limit.new(name, count, interval, semaphore: semaphore, namespace: namespace) }
  
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end

  before(:each) do
    pool.with { |r| r.flushdb }
  end

  describe '#init' do
    it 'creates a new limit' do
      expect(producer.init(limit)).to be true
    end
  end

  describe '#update' do
    it 'calls init under the hood' do
      expect(producer.update(limit)).to be true
      expect(producer.info(limit).limit.tokens).to eq(limit.max_tokens)
    end
  end

  describe '#list' do
    before do
      producer.init(Rapidity::Share::Limit.new('limit_1', 20, 100, namespace: namespace))
      producer.init(Rapidity::Share::Limit.new('limit_2', 30, 200, namespace: namespace))
      producer.init(Rapidity::Share::Limit.new('limit_3', 40, 300, namespace: namespace))
    end
    
    it 'return limits list' do
      expect(producer.list("#{namespace}:*").size).to be 3
    end
    
    it 'return empty list' do
      pool.with { |r| r.flushdb }
      expect(producer.list("#{namespace}:*")).to eq([])
    end
  end

  describe '#check_queue' do
    it 'semaphore' do
      limit = Rapidity::Share::Limit.new('limit_1', 20, 100, namespace: namespace)
      producer.init(limit)

      result = producer.check_queue(limit)
      expect(result.success).to eq(true)
    end

    it 'key_not_exist' do
      result = producer.check_queue('key_not_exist')
      
      expect(result.success).to eq(false)
    end
  end

  describe '#acquire_queue' do
    let(:limit_1) { Rapidity::Share::Limit.new('limit_1', 20, 100, max_queue: 20, namespace: namespace) }
    let(:limit_2) { Rapidity::Share::Limit.new('limit_2', 20, 100, max_queue: 20, namespace: namespace) }

    before do
      producer.init(limit_1)
      producer.init(limit_2)
    end

    context 'when passing arguments as an array of strings' do
      it 'successfully extracts limit names' do
        result = producer.acquire_queue([limit_1.name, limit_2.name], count: 5)
        expect(result.success).to eq(true)
        expect(result.tokens).to eq(5)
      end
    end

    context 'when passing a single limit object' do
      it 'wraps it into an array and processes successfully' do
        result = producer.acquire_queue(limit_1, count: 5)
        expect(result.success).to eq(true)
        expect(result.tokens).to eq(5)
      end
    end

    context 'when passing a single limit string' do
      it 'wraps it into an array and processes successfully' do
        result = producer.acquire_queue(limit_1.name, count: 5)
        expect(result.success).to eq(true)
        expect(result.tokens).to eq(5)
      end
    end
  end

  context "base" do
    let (:limit) {Rapidity::Share::Limit.new('limit_1', 20, 100, max_queue: 20, namespace: namespace)}
    
    describe '#reset' do
      it 'reset' do
        producer.init(limit)
        info = producer.info(limit)
        expect(info.limit.tokens).to eq(20)

        result = producer.acquire_queue([limit], count: 5)
        expect(result.success).to eq(true)
        expect(result.tokens).to eq(5)
        info = producer.info(limit)
        expect(info.limit.semaphore).to eq(15)
        producer.reset(limit)
        
        info = producer.info(limit)
        expect(info.limit.semaphore).to eq(20)
      end

      it 'key_not_exist' do
        result = producer.reset('key_not_exist')
        expect(result.success).to be(false)
      end
    end

    describe '#delete' do
      it 'delete' do
        producer.init(limit)
        result = producer.delete(limit)
        expect(result.success).to eq(true)
      end

      it 'key_not_exist' do
        result = producer.delete('key_not_exist')
        expect(result.success).to eq(false)
      end
    end

    describe '#info' do
      it 'info' do
        producer.init(limit)
        result = producer.info(limit)
        expect(result.success).to eq(true)
        expect(result.limit.tokens).to eq(limit.max_tokens)
      end

      it 'key_not_exist' do
        result = producer.info('key_not_exist')
        expect(result.success).to eq(false)
      end
    end
  end
end