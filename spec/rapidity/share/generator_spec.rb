require 'active_support/all'

RSpec.describe Rapidity::Share::Generator do
  let(:namespace){ "test_workplace" }
  subject(:generator){ described_class.new(pool, namespace:) }
  let(:count){ 20 }
  let(:name){ "limit" }
  let(:interval){ 600 }
  let(:queue){ 20 }
  let(:limit) { Rapidity::Share::Limit.new(name, count, interval, queue:) }
  
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end

  before(:each) do
    pool.with { |r| r.flushdb }
  end

  it '#init' do
    expect(generator.init(limit)).to be true
  end

  describe '#list' do
    before do
      generator.init(Rapidity::Share::Limit.new('limit_1', 20, 100))
      generator.init(Rapidity::Share::Limit.new('limit_2', 30, 200))
      generator.init(Rapidity::Share::Limit.new('limit_3', 40, 300))
    end
    
    it 'return limits list' do
      expect(generator.list("#{namespace}:*").size).to be 3
    end
    
    it 'return empty list' do
      pool.with { |r| r.flushdb }
      expect(generator.list("#{namespace}:*")).to eq([])
    end
  end

  describe '#check_queue' do
    it 'queue' do
      limit = Rapidity::Share::Limit.new('limit_1', 20, 100)
      generator.init(limit)

      result = generator.check_queue(limit)
      expect(result.success).to eq(true)
    end

    it 'key_not_exist' do
      result = generator.check_queue('key_not_exist')
      
      expect(result.success).to eq(false)
    end
  end

  context "base" do
    let (:limit) {Rapidity::Share::Limit.new('limit_1', 20, 100, max_queue: 20)}
    
    describe '#reset' do
      it 'reset' do
        generator.init(limit)
        info = generator.info(limit)
        expect(info.limit.tokens).to eq(20)

        result = generator.acquire_queue(limit, count: 5)
        expect(result.success).to eq(true)
        expect(result.tokens).to eq(5)
        info = generator.info(limit)
        expect(info.limit.queue).to eq(15)
        generator.reset(limit)
        
        info = generator.info(limit)
        expect(info.limit.queue).to eq(20)
      end

      it 'key_not_exist' do
        result = generator.reset('key_not_exist')
        expect(result.success).to be(false)
      end
    end

    describe '#delete' do
      it 'delete' do
        generator.init(limit)
        result = generator.delete(limit)
        expect(result.success).to eq(true)
      end

      it 'key_not_exist' do
        result = generator.delete('key_not_exist')
        expect(result.success).to eq(false)
      end
    end

    describe '#info' do
      it 'info' do
        generator.init(limit)
        result = generator.info(limit)
        expect(result.success).to eq(true)
        expect(result.limit.tokens).to eq(limit.max_tokens)
      end

      it 'key_not_exist' do
        result = generator.info('key_not_exist')
        expect(result.success).to eq(false)
      end
    end
  end
end