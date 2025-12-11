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

  it '#init' do
		expect(limiter.init(limit)).to be true
  end


	describe 'base' do
		let(:namespace){ "test_workplace_1" }
		
		before do
			limiter.init(Rapidity::Share::Limit.new('limit_1', 20, 100))
			limiter.init(Rapidity::Share::Limit.new('limit_2', 30, 200))
			limiter.init(Rapidity::Share::Limit.new('limit_3', 40, 300))
		end
		
		it '#list' do
			expect(limiter.list("#{namespace}:*").size).to be 3
  	end
  end
end