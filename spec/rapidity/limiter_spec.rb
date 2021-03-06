require 'active_support/all'


RSpec.describe Rapidity::Limiter do
  let(:name){ "test#{rand(9_999_999_999_999)}" }

  subject(:limiter){ described_class.new(pool, name: name, threshold: limit, interval: interval) }
  let(:limit){ 10 }
  let(:interval){ 1 }
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end

  it '#obtain' do
    expect(limiter.obtain(5)).to eq(5)
    expect(limiter.obtain(5)).to eq(5)
    expect(limiter.obtain(5)).to eq(0)
  end

  it '#remains' do
    expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(-5)
    expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(-5)
    expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(0)
  end

  context 'with sleep' do
    it '#obtain' do
      expect(limiter.obtain(5)).to eq(5)
      expect(limiter.obtain(5)).to eq(5)
      expect(limiter.obtain(5)).to eq(0)
      sleep 1.1
      expect(limiter.obtain(5)).to eq(5)
      expect(limiter.obtain(5)).to eq(5)
      expect(limiter.obtain(5)).to eq(0)
    end

    it '#remains' do
      expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(-5)
      expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(-5)
      expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(0)

      sleep 1.1

      expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(-5)
      expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(-5)
      expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(0)
    end
  end

  context 'multiaccess' do
    subject(:limiter2) do
      described_class.new(pool, name: name, threshold: limit, interval: interval)
    end
    subject(:limiter3) do
      described_class.new(pool, name: name, threshold: limit, interval: interval)
    end

    it '#obtain' do
      expect(limiter.obtain(5)).to eq(5)
      expect(limiter2.obtain(5)).to eq(5)
      expect(limiter3.obtain(5)).to eq(0)
    end

    it '#remains' do
      expect{ limiter.obtain(5) }.to change{ limiter.remains }.by(-5)
      expect{ limiter2.obtain(5) }.to change{ limiter.remains }.by(-5)
      expect{ limiter3.obtain(5) }.to change{ limiter.remains }.by(0)
    end
  end
end

