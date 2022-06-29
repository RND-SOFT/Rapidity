# Rapidity

[![Gem Version](https://badge.fury.io/rb/rapidity.svg)](https://rubygems.org/gems/rapidity)
[![Gem](https://img.shields.io/gem/dt/rapidity.svg)](https://rubygems.org/gems/rapidity/versions)
[![YARD](https://badgen.net/badge/YARD/doc/blue)](http://www.rubydoc.info/gems/rapidity)

[![Coverage](https://lysander.rnds.pro/api/v1/badges/rapidity_coverage.svg)](https://lysander.rnds.pro/api/v1/badges/rapidity_coverage.html)
[![Quality](https://lysander.rnds.pro/api/v1/badges/rapidity_quality.svg)](https://lysander.rnds.pro/api/v1/badges/rapidity_quality.html)
[![Outdated](https://lysander.rnds.pro/api/v1/badges/rapidity_outdated.svg)](https://lysander.rnds.pro/api/v1/badges/rapidity_outdated.html)
[![Vulnerabilities](https://lysander.rnds.pro/api/v1/badges/rapidity_vulnerable.svg)](https://lysander.rnds.pro/api/v1/badges/rapidity_vulnerable.html)

Simple but fast Redis-backed distributed rate limiter. Allows you to specify time interval and count within to limit distributed operations.

Features:

- extremly simple
- free from race condition through LUA scripting
- fast

[Article(russian) about gem.](https://blog.rnds.pro/029-rapidity/?utm_source=github&utm_medium=repo&utm_campaign=rnds)

## Usage

Rapidity has two variants:

- simple `Rapidity::Limiter` to handle single distibuted counter
- complex `Rapidity::Composer` to handle multiple counters at once

### Single conter with concurrent access

```ruby
pool = ConnectionPool.new(size: 10) do
  Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
end

# allow no more 10 requests within 5 seconds
limiter = Rapidity::Limiter.new(pool, name: 'requests', threshold: 10, interval: 5)

loop do
  # try to obtain 3 requests at once
  quota = limiter.obtain(3).times do
    make_request
  end

  if quota == 0
    # no more requests allowed within interval
    sleep 1
  end
end

```

### Multiple counters

```ruby
pool = ConnectionPool.new(size: 10) do
  Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
end

LIMITS = [
  { interval: 1, threshold: 2 },        # no more 2 requests per second
  { interval: 60, threshold: 200 },     # no more 200 requests per minute
  { interval: 86400, threshold: 10000 } # no more 10k requests per day
]

limiter = Rapidity::Composer.new(pool, name: 'requests', limits: LIMITS)

loop do
  # try to obtain 3 requests at once
  quota = limiter.obtain(3).times do
    make_request
  end

  if quota == 0
    # no more requests allowed within interval
    puts limiter.remains # inspect current limits
    sleep 1
  end
end
```

## Installation

It's a gem:

```bash
  gem install rapidity
```

There's also the wonders of [the Gemfile](http://bundler.io):

```ruby
  gem 'rapidity'
```

## Special Thanks

- [WeTransfer/prorate](https://github.com/WeTransfer/prorate) for LUA-examples
