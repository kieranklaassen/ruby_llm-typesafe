# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load'
require 'fileutils'

require 'vcr'
require 'ruby_llm/providers/typesafe'
require 'webmock/rspec'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |file| require file }
