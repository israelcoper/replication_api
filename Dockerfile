# syntax=docker/dockerfile:1
# Development-ready Dockerfile for Rails 7.2 API

ARG RUBY_VERSION=3.2.2
FROM ruby:$RUBY_VERSION-slim

# Set working directory
WORKDIR /rails

# Install packages needed for Rails development
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libpq-dev \
      libyaml-dev \
      pkg-config \
      nodejs \
      yarn \
      curl \
      libjemalloc2 \
      libvips \
      postgresql-client \
      && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Set development environment
ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

# Copy Gemfiles first for caching
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy the rest of the application code
COPY . .

# Expose Rails port for development
EXPOSE 3000

# Optional: create tmp, log, storage directories
RUN mkdir -p tmp log storage && \
    chown -R 1000:1000 tmp log storage

# Use non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash rails
USER 1000:1000

# Entry point: optionally run DB setup
# ENTRYPOINT ["bash", "-c", "bin/rails db:prepare && exec bash"]

# Default command: run Rails server in development
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
