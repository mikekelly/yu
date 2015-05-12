FROM ruby:latest

# Install build dependencies:
# RUN yum groupinstall -y development

WORKDIR /tmp
COPY Gemfile /tmp/Gemfile
COPY Gemfile.lock /tmp/Gemfile.lock
ADD ./vendor/cache /tmp/vendor/cache

RUN bundle install --local --no-cache

ADD ./ /app
WORKDIR /app
