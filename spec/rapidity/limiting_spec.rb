require 'active_support/all'

RSpec.describe Rapidity do
  # возьмем лимиты кратные документации
  # в минуту - 110;     [60, 110]          - 1,8 в секунду
  # в час 6 500;        [3600,6500]        - 1,8 в секунду
  # в неделю - 650 000; [604800, 650000]   - 1 в секунду
  # в месяц - 2 000 000.[2592000, 2000000] - 0,7 в секунду

  LIMITS = [
    [1, 2],   # 2 за секунду    ~ 1,8
    [5, 9],   # 9 за 5 секунд   ~ 1,8
    [20, 20], # 20 за 20 секунд ~ 1
    [60, 42]  # 42 за 60 секунд ~ 0,7
  ].freeze

  let(:name){ "test#{rand(9_999_999_999_999)}" }
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end

  MX = Monitor.new

  def make_requests(limit:, interval:, duration:)
    @requests = []

    @limiter = Rapidity::Limiter.new(pool, name: name, threshold: limit, interval: interval)

    with_duration(duration) do
      tokens = @limiter.obtain(10)
      tokens.times do
        MX.synchronize do
          @requests.push Time.now
        end
        sleep 0.13
      end
    end

    @requests
  end

  def with_duration(duration)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f
    while (Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f - start) < duration
      yield
      sleep 0.5
    end
  end

  def check_limit(interval, count, requests)
    failed = nil
    requests.each_with_index do |start, i|
      finish = start + interval.seconds
      window = requests.select do |r|
        r.to_f >= start.to_f && r.to_f < finish.to_f
      end

      next if window.size <= (count + 1)

      msg = "Limit[#{count}/#{interval}] count: #{window.size} limit: #{count + 1} overcomed by #{window.size - (count + 1)} at #{i} with time #{start}-#{finish}"
      ap requests
      failed ||= msg
      puts msg
      return failed
    end
    failed
  end

  describe 'Single limits' do
    LIMITS.each do |(interval, count)|
      it "Limit #{count}/#{interval}" do
        requests = make_requests(limit: count, interval: interval, duration: (interval * 1.5).ceil)
        expect(requests).not_to be_empty

        expect(requests.count).to be > count
        expect(requests.count).to eq(count * 2)

        failure = check_limit(interval, count, requests)
        expect(failure).to be_nil, failure
      end
    end
  end

  def start_publisher(requests, limits, duration, delay: 0.13, debug: false)
    limiter = Rapidity::Composer.new(pool, name: name, limits: limits)

    with_duration(duration) do

      tokens = limiter.obtain(1)
      tokens.times do
        c = MX.synchronize do
          requests.push Time.now
          requests.count
        end
        ap "[#{Thread.current.object_id}][#{Time.now}](#{c}) #{limiter.remains}" if debug
        sleep delay
      end

    end
  end

  it 'Complex limits' do
    limits = LIMITS.map do |interval, limit|
      { interval: interval, threshold: limit }
    end

    @requests = []

    start_publisher(@requests, limits, 90)

    expect(@requests).not_to be_empty
    expect(@requests.count).to be >= 42

    limits.each do |limit|
      failure = check_limit(limit[:interval], limit[:threshold], @requests)
      expect(failure).to be_nil, failure
    end
  end

  it 'Parallel Complex limits' do
    limits = LIMITS.map do |interval, limit|
      { interval: interval, threshold: limit }
    end

    @requests = []

    threads = 4.times.map do
      Thread.new do
        start_publisher(@requests, limits, 90)
      end
    end

    threads.each(&:join)

    expect(@requests).not_to be_empty
    expect(@requests.count).to be >= 42

    limits.each do |limit|
      failure = check_limit(limit[:interval], limit[:threshold], @requests)
      expect(failure).to be_nil, failure
    end
  end

  5.times do |i|
    it "Highload randomize #{i}" do
      last_interval = 0
      last_limit = 0
      limits = 5.times.map do
        last_interval = last_interval + 1 + rand(5)
        last_limit += rand(1000)
        { interval: last_interval, threshold: last_limit }
      end

      @requests = []

      threads = 5.times.map do
        Thread.new do
          start_publisher(@requests, limits, (last_interval * 1.5).ceil, delay: 0.05)
        end
      end

      threads.each(&:join)

      expect(@requests).not_to be_empty

      limits.each do |limit|
        failure = check_limit(limit[:interval], limit[:threshold], @requests)
        expect(failure).to be_nil, failure
      end
    end
  end
end

