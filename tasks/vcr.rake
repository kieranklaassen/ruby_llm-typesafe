# frozen_string_literal: true

require 'fileutils'

namespace :vcr do
  desc 'Re-record every VCR cassette against the live TypeSafe API (needs TYPESAFE_API_KEY)'
  task :record do
    require 'dotenv/load'
    abort 'Set TYPESAFE_API_KEY (or add it to .env) to record cassettes' if ENV.fetch('TYPESAFE_API_KEY', '').empty?

    cassette_dir = File.expand_path('../spec/fixtures/vcr_cassettes', __dir__)
    FileUtils.rm_rf(cassette_dir)
    FileUtils.mkdir_p(cassette_dir)

    puts 'Recording cassettes for the live TypeSafe specs...'
    sh 'bundle exec rspec --tag live'
    puts 'Done. Review the new cassettes for sensitive information before committing.'
  end
end
