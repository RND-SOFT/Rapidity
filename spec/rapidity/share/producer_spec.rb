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

  it '#init' do
    expect(producer.init(limit)).to be true
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

  context "base" do
    let (:limit) {Rapidity::Share::Limit.new('limit_1', 20, 100, max_queue: 20, namespace: namespace)}
    
    describe '#reset' do
      it 'reset' do
        producer.init(limit)
        info = producer.info(limit)
        expect(info.limit.tokens).to eq(20)

        result = producer.acquire_queue(limit, count: 5)
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