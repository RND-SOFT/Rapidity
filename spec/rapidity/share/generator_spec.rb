require 'active_support/all'

RSpec.describe Rapidity::Share::Generator do
  let(:namespace){ "test_workplace" }
  subject(:limiter){ described_class.new(pool, namespace:) }
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
    expect(limiter.init(limit)).to be true
  end

  describe '#list' do
    before do
      limiter.init(Rapidity::Share::Limit.new('limit_1', 20, 100))
      limiter.init(Rapidity::Share::Limit.new('limit_2', 30, 200))
      limiter.init(Rapidity::Share::Limit.new('limit_3', 40, 300))
    end
    
    it 'return limits list' do
      expect(limiter.list("#{namespace}:*").size).to be 3
    end
    
    it 'return empty list' do
      pool.with { |r| r.flushdb }
      expect(limiter.list("#{namespace}:*")).to eq([])
    end
  end

  describe '#check_queue' do
    it 'return queue state' do
      limiter.init(limit)
      expect(limiter.check_queue(limiter.send(:redis_key, name))).to be >= 0
    end

    it 'return error if limit not exist' do
      result = limiter.check_queue(limiter.send(:redis_key, 'nonexistent'))
      expect(result).to be_a(Hash)
      expect(result['error']).to eq('key_not_found')
    end
  end

  describe '#reset' do
    it 'сбрасывает состояние лимита' do
      limiter.init(limit)
      expect(limiter.reset(limiter.send(:redis_key, name))).to eq({'OK' => true})
    end

    it 'возвращает ошибку для несуществующего ключа' do
      result = limiter.reset(limiter.send(:redis_key, 'nonexistent'))
      expect(result).to be_a(Hash)
      expect(result['error']).to eq('key_not_found')
    end
  end

  describe '#delete' do
    it 'удаляет лимит' do
      limiter.init(limit)
      expect(limiter.delete(limiter.send(:redis_key, name))).to eq({'OK' => true})
    end

    it 'возвращает ошибку для несуществующего ключа' do
      result = limiter.delete(limiter.send(:redis_key, 'nonexistent'))
      expect(result).to be_a(Hash)
      expect(result['error']).to eq('key_not_found')
    end
  end

  describe '#info' do
    it 'возвращает информацию о лимите' do
      limiter.init(limit)
      info = limiter.info(limiter.send(:redis_key, name))
      expect(info).to be_a(Hash)
      expect(info['max_tokens'].to_i).to eq(count)
    end

    it 'возвращает ошибку для несуществующего ключа' do
      result = limiter.info(limiter.send(:redis_key, 'nonexistent'))
      expect(result).to be_a(Hash)
      expect(result['error']).to eq('key_not_found')
    end
  end

  describe '#update' do
    it 'обновляет существующий лимит' do
      limiter.init(limit)
      updated_limit = Rapidity::Share::Limit.new(name, 50, 800, queue: 30)
      expect(limiter.update(updated_limit)).to be true
    end
  end
end