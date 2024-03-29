ARG RUBY_VERSION=2.5

FROM ruby:${RUBY_VERSION}-alpine

WORKDIR /home/app

RUN mkdir -p /usr/local/etc \
  && { \
    echo 'install: --no-document'; \
    echo 'update: --no-document'; \
  } >> /usr/local/etc/gemrc \
  && echo 'gem: --no-document' > ~/.gemrc

RUN set -ex \
  && apk add --no-cache build-base git curl

ADD Gemfile Gemfile.lock *.gemspec /home/app/
ADD lib/rapidity/version.rb /home/app/lib/rapidity/

RUN set -ex \
  && gem install bundler && gem update bundler \
  && bundle install --jobs=3 \
  && gem cleanup  \
  && rm -rf /tmp/* /var/tmp/* /usr/src/ruby /root/.gem /usr/local/bundle/cache

ADD . /home/app/

RUN set -ex \
  && bundle install --jobs=3 \
  && gem cleanup  \
  && rm -rf /tmp/* /var/tmp/* /usr/src/ruby /root/.gem /usr/local/bundle/cache

CMD ["tail", "-f", "/dev/null"]


