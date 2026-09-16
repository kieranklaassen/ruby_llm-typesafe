# frozen_string_literal: true

RubyLLM.configure do |config|
  config.max_retries = 0
  config.retry_backoff_factor = 0
  config.retry_interval = 0
  config.retry_interval_randomness = 0
end

# Specs tagged :live replay (or record) the real TypeSafe API and get this
# context automatically. Untagged specs that only need configured keys
# include it by name.
RSpec.shared_context 'with configured RubyLLM' do
  before do
    RubyLLM.configure do |config|
      config.typesafe_api_key = ENV.fetch('TYPESAFE_API_KEY', 'test')
      config.typesafe_api_base = ENV.fetch('TYPESAFE_API_BASE', nil)
      # Disable retries in tests for deterministic, fast failures.
      config.max_retries = 0
      config.retry_backoff_factor = 0
      config.retry_interval = 0
      config.retry_interval_randomness = 0
    end
  end
end

RSpec.configure do |config|
  config.include_context 'with configured RubyLLM', :live
end
