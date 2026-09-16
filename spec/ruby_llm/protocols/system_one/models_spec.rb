# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Protocols::SystemOne::Models do
  include_context 'with configured RubyLLM'

  let(:provider) { RubyLLM::Providers::TypeSafe.new(RubyLLM.config) }
  let(:protocol) { RubyLLM::Protocols::SystemOne.new(provider) }

  describe '#models_url' do
    it 'lists models from the v1 endpoint' do
      expect(protocol.send(:models_url)).to eq('v1/models')
    end
  end

  describe '#parse_list_models_response' do
    let(:response) do
      instance_double(
        Faraday::Response,
        body: {
          'models' => [
            { 'name' => 'jev-latest', 'description' => "The latest iteration of TypeSafe's System One Model: Jev",
              'release_date' => '2026-09-10T18:38:01.391457+00:00' }
          ]
        }
      )
    end

    it 'records the name, description, and release date without inventing limits' do
      models = described_class.parse_list_models_response(response, 'typesafe')

      expect(models.size).to eq(1)
      model = models.first
      expect(model.id).to eq('jev-latest')
      expect(model.name).to eq('jev-latest')
      expect(model.provider).to eq('typesafe')
      expect(model.family).to eq('jev')
      expect(model.created_at.to_date.to_s).to eq('2026-09-10')
      expect(model.context_window).to be_nil
      expect(model.max_output_tokens).to be_nil
      expect(model.capabilities).to eq(['structured_output'])
      expect(model.modalities.input).to eq(['text'])
      expect(model.modalities.output).to eq(['text'])
      expect(model.type).to eq(:chat)
      expect(model.metadata[:description]).to include('System One Model')
    end

    it 'rejects an unexpected body' do
      bad = instance_double(Faraday::Response, body: { 'data' => [] })

      expect { described_class.parse_list_models_response(bad, 'typesafe') }
        .to raise_error(RubyLLM::Error, /unexpected models list/)
    end
  end

  describe '#list_models', :live do
    it 'lists the System One models available to the account' do
      models = provider.list_models

      expect(models).to all(have_attributes(provider: 'typesafe'))
      expect(models.map(&:id)).to include('jev-latest')
      expect(models).to all(satisfy { |model| model.supports?(:structured_output) })
    end
  end
end
