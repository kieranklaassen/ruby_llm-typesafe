# frozen_string_literal: true

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock

  # Don't record new HTTP interactions when running in CI
  config.default_cassette_options = { record: ENV['CI'] ? :none : :once }

  FileUtils.mkdir_p(config.cassette_library_dir)

  # Allow HTTP connections when no cassette is in use. A pull request without cassettes fails by design.
  config.allow_http_connections_when_no_cassette = true

  # Filter out API keys from the recorded cassettes
  config.filter_sensitive_data('<TYPESAFE_API_KEY>') { ENV.fetch('TYPESAFE_API_KEY', nil) }
  config.filter_sensitive_data('<TYPESAFE_API_BASE>') { ENV.fetch('TYPESAFE_API_BASE', nil) }
  config.filter_sensitive_data('<X_TYPESAFE_REQUEST_ID>') do |interaction|
    interaction.response.headers['X-Typesafe-Request-Id']&.first
  end

  config.before_record do |interaction|
    if interaction.request.headers['Authorization']
      interaction.request.headers['Authorization'] =
        interaction.request.headers['Authorization'].map do |value|
          value.match?(/\ABearer /i) ? 'Bearer <AUTH_TOKEN>' : value
        end
    end

    if interaction.response.headers['Set-Cookie']
      interaction.response.headers['Set-Cookie'] = interaction.response.headers['Set-Cookie'].map { '<COOKIE>' }
    end
  end
end
