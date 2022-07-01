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
    requests = []

    @limiter = Rapidity::Limiter.new(pool, name: name, threshold: limit, interval: interval)

    with_duration(duration) do
      tokens, time = @limiter.obtain(10, with_time: true)
      tokens.times do
        requests.push time
        sleep 0.13
      end
    end

    requests
  end

  def with_duration(duration, delay: 0.5)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f
    while (Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f - start) < duration
      yield
      sleep delay
    end
  end

  def check_limit(interval, count, requests)
    failed = nil
    finish = start = requests.first
    limit = count# + 1

    while requests.any? do
      start = finish
      finish = start + interval.seconds

      window, requests = requests.partition do |r|
        r.to_f >= start.to_f && r.to_f < finish.to_f
      end


      next if window.size <= limit

      msg = "Limit[#{count}/#{interval}] count: #{window.size} limit: #{limit} overcomed by #{window.size - limit} with time [#{start.strftime('%H:%M:%S.%L')}-#{finish.strftime('%H:%M:%S.%L')}]"
      ap window
      ap "rest:"
      ap requests
      failed ||= msg
      puts msg
      return failed
    end

    failed
  end

  def check_limit_strict(interval, count, requests)
    failed = nil
    requests.each_with_index do |start, i|
      finish = start + interval.seconds

      window = requests.select do |r|
        r.to_f >= start.to_f && r.to_f < finish.to_f
      end

      next if window.size <= (count + 1)

      msg = "Limit[#{count}/#{interval}] count: #{window.size} limit: #{count + 1} pos #{i} overcomed by #{window.size - (count + 1)} with time [#{start.strftime('%H:%M:%S.%L')}-#{finish.strftime('%H:%M:%S.%L')}]"
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
        requests.sort!
        expect(requests).not_to be_empty

        expect(requests.count).to be > count
        expect(requests.count).to eq(count * 2)

        failure = check_limit(interval, count, requests)
        expect(failure).to be_nil, failure
      end
    end
  end

  def start_publisher(limits, duration, delay: 0.13, debug: false)
    limiter = Rapidity::Composer.new(pool, name: name, limits: limits)
    requests = []
    blocked = 0

    ap "[#{Thread.current.object_id}][#{Time.now}](#{requests.count}) #{limits}" if debug

    with_duration(duration, delay: delay) do
      tokens, time = limiter.obtain(1, with_time: true)

      tokens.times do
        #ap "[#{Thread.current.object_id}][#{Time.now}](#{requests.count}) #{limiter.remains}" if debug
        requests.push time
      end


      if tokens == 0
        ap "BLOCKED [#{Thread.current.object_id}][#{Time.now}](#{requests.count}) #{limiter.remains}" if debug
        blocked += 1
        sleep rand(5) / 10.0
      end
    end

    [requests, blocked]
  end

  it 'Complex limits' do
    limits = LIMITS.map do |interval, limit|
      { interval: interval, threshold: limit }
    end

    requests, blocked = start_publisher(limits, 90)
    requests.sort!

    expect(requests).not_to be_empty
    expect(requests.count).to be >= 42
    expect(blocked).to be >= 0

    limits.each do |limit|
      failure = check_limit(limit[:interval], limit[:threshold], requests)
      expect(failure).to be_nil, failure
    end
  end

  it 'Parallel Complex limits' do
    limits = LIMITS.map do |interval, limit|
      { interval: interval, threshold: limit }
    end

    requests = []
    blocked = 0

    threads = 4.times.map do
      Thread.new do
        start_publisher(limits, 90)
      end
    end

    threads.map do |th|
      r, b = th.value
      requests += r
      blocked += b
    end

    requests.sort!

    expect(requests).not_to be_empty
    expect(blocked).to be >= 0
    expect(requests.count).to be >= 42

    limits.each do |limit|
      failure = check_limit(limit[:interval], limit[:threshold], requests)
      expect(failure).to be_nil, failure
    end
  end

  describe "Highload randomize" do
    5.times do |i|
      static_last_interval = 0
      static_last_limit = 0
      static_limits = 5.times.map do
        static_last_interval = static_last_interval + 1 + rand(5)
        static_last_limit += rand(100)
        { interval: static_last_interval, threshold: static_last_limit }
      end


      it "No #{i} #{static_limits}" do
        last_interval = static_last_interval
        limits = static_limits

        requests = []
        blocked = 0

        threads = 5.times.map do
          Thread.new do
            start_publisher(limits, (last_interval * 1.5).ceil, delay: 0.01)
          end
        end

        threads.map do |th|
          r, b = th.value
          requests += r
          blocked += b
        end

        requests.sort!

        expect(requests).not_to be_empty
        expect(blocked).to be >= 0

        limits.each do |limit|
          failure = check_limit(limit[:interval], limit[:threshold], requests)
          expect(failure).to be_nil, failure
        end
      end
    end
  end
end

