require 'active_support/all'

RSpec.describe Rapidity::Share::Limit do
  
  it '#valid?' do
    limit = described_class.new('test', 100, 60)
    expect(limit.valid?).to be true
  end

  it 'raise_error' do
    expect { described_class.new('test', 0, 60) }.to raise_error(ArgumentError)
    expect { described_class.new('test', 100, 0) }.to raise_error(ArgumentError)
  end

  it '#from_hash' do
    hash = { max_tokens: 50, interval: 30, tokens: 25, last_used: Time.now.to_i }
    limit = described_class.from_hash('test', **hash)
    expect(limit.max_tokens).to eq(50)
    expect(limit.tokens).to eq(25)
  end

  it '#persisted?' do
    limit1 = described_class.new('test1', 100, 60)
    limit2 = described_class.new('test2', 100, 60, last_used: Time.now.to_i)
    expect(limit1.persisted?).to be false
    expect(limit2.persisted?).to be true
  end
  
end