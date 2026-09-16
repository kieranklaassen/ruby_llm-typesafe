# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::TypeSafe do
  include_context 'with configured RubyLLM'

  let(:provider) { described_class.new(RubyLLM.config) }

  it 'is registered with RubyLLM as :typesafe' do
    expect(RubyLLM::Provider.resolve(:typesafe)).to eq(described_class)
    expect(described_class.slug).to eq('typesafe')
    expect(described_class.display_name).to eq('TypeSafe')
  end

  it 'speaks the System One protocol by default' do
    expect(described_class.protocols).to eq(system_one: RubyLLM::Protocols::SystemOne)
    expect(described_class.default_protocol).to eq(:system_one)
  end

  it 'is a remote provider whose models come from the packaged catalog' do
    expect(described_class.remote?).to be(true)
    expect(described_class.assume_models_exist?).to be(false)
    expect(RubyLLM::Provider.model_registry_files[:typesafe]).to end_with('/models.json')
  end

  it 'declares provider configuration' do
    expect(described_class.configuration_options).to eq(%i[typesafe_api_key typesafe_api_base])
    expect(described_class.configuration_requirements).to eq(%i[typesafe_api_key])
  end

  describe '#api_base' do
    it 'talks to the TypeSafe API' do
      expect(provider.api_base).to eq('https://api.typesafe.ai')
    end

    it 'honors a configured base' do
      RubyLLM.config.typesafe_api_base = 'https://typesafe.example.com'

      expect(provider.api_base).to eq('https://typesafe.example.com')
    ensure
      RubyLLM.config.typesafe_api_base = nil
    end
  end

  describe '#headers' do
    it 'authenticates with a Bearer authorization header' do
      RubyLLM.config.typesafe_api_key = 'typesafe-key'

      expect(provider.headers).to eq('Authorization' => 'Bearer typesafe-key')
    end
  end

  describe '#parse_error' do
    def response_for(body)
      instance_double(Faraday::Response, body: body)
    end

    it 'reads the message out of an API usage error' do
      response = response_for('detail' => { 'error_type' => 'api_usage_error', 'message' => 'Unknown model: nope' })

      expect(provider.parse_error(response)).to eq('Unknown model: nope')
    end

    it 'flattens 422 validation details into one readable line' do
      response = response_for(
        'detail' => [
          { 'type' => 'missing', 'loc' => %w[body state], 'msg' => 'Field required' },
          { 'type' => 'union_tag_invalid', 'loc' => %w[body questions bogus], 'msg' => "Input tag 'nope' is unknown" }
        ]
      )

      expect(provider.parse_error(response))
        .to eq("state: Field required; questions.bogus: Input tag 'nope' is unknown")
    end

    it 'parses the JSON string the error middleware hands it' do
      response = response_for('{"detail":{"error_type":"authentication_error","message":"Invalid API key"}}')

      expect(provider.parse_error(response)).to eq('Invalid API key')
    end

    it 'falls back to the generic parser for standard error bodies' do
      expect(provider.parse_error(response_for('error' => { 'message' => 'Bad request' }))).to eq('Bad request')
      expect(provider.parse_error(response_for('message' => 'Bad request'))).to eq('Bad request')
      expect(provider.parse_error(response_for('detail' => 'Plain detail'))).to eq('Plain detail')
      expect(provider.parse_error(response_for('<html>Bad Gateway</html>'))).to eq('<html>Bad Gateway</html>')
    end

    it 'leaves unfamiliar bodies to RubyLLM::Error' do
      expect(provider.parse_error(response_for('detail' => { 'code' => 'weird' }))).to be_nil
      expect(provider.parse_error(response_for(nil))).to be_nil
      expect(provider.parse_error(response_for(''))).to be_nil
    end
  end

  describe 'configuration' do
    it 'raises a ConfigurationError that names the missing key without leaking values' do
      RubyLLM.config.typesafe_api_key = nil

      expect { described_class.new(RubyLLM.config) }.to raise_error(RubyLLM::ConfigurationError) do |error|
        expect(error.message).to include('TypeSafe provider is not configured')
        expect(error.message).to include("config.typesafe_api_key = ENV['TYPESAFE_API_KEY']")
      end
    end

    it 'exposes typesafe_api_key, typesafe_api_base, and typesafe_protocol on Configuration' do
      config = RubyLLM::Configuration.new

      expect(config).to respond_to(:typesafe_api_key=, :typesafe_api_base=, :typesafe_protocol=)
      expect(config.typesafe_api_key).to be_nil
    end

    it 'sends the configured key only in the Authorization header' do
      RubyLLM.config.typesafe_api_key = 'header-only-key'
      stub_systemone

      typesafe_chat.ask(support_state)

      request = systemone_requests.fetch(0)
      expect(request.headers['Authorization']).to eq('Bearer header-only-key')
      expect(request.uri.to_s).not_to include('header-only-key')
      expect(request.body).not_to include('header-only-key')
    end
  end
end
