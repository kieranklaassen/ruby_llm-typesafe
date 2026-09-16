# frozen_string_literal: true

desc 'Refresh the packaged TypeSafe model catalog from GET /v1/models'
task :models do
  require 'dotenv/load'
  require_relative '../lib/ruby_llm/providers/typesafe'

  RubyLLM.configure do |config|
    config.typesafe_api_key = ENV.fetch('TYPESAFE_API_KEY', nil)
    config.typesafe_api_base = ENV.fetch('TYPESAFE_API_BASE', nil)
  end

  provider = RubyLLM::Provider.resolve!(:typesafe).new(RubyLLM.config)
  models = provider.list_models
  abort 'TypeSafe returned no models' if models.empty?

  RubyLLM::Models.new(models).save_to_json(File.expand_path('../models.json', __dir__))
  puts "Saved #{models.size} models to models.json: #{models.map(&:id).join(', ')}"
end
