# frozen_string_literal: true

require 'spec_helper'
require 'json_schemer'

RSpec.describe RubyLLM::Models do
  include_context 'with configured RubyLLM'

  let(:models_json_path) { File.expand_path('../../models.json', __dir__) }
  let(:models_data) { JSON.parse(File.read(models_json_path)) }

  it 'validates that models.json conforms to the registry schema' do
    registry_schema = {
      '$schema' => 'https://json-schema.org/draft/2020-12/schema',
      'type' => 'array',
      'items' => RubyLLM::Models::Schema.json_schema
    }
    registry = JSONSchemer.schema(registry_schema)
    validation_errors = registry.validate(models_data).map { |error| "#{error['data_pointer']}: #{error['error']}" }

    expect(validation_errors).to be_empty, "models.json has validation errors:\n#{validation_errors.join("\n")}"
  end

  it 'packages only TypeSafe models with structured output and nothing it cannot do' do
    expect(models_data).not_to be_empty
    expect(models_data.map { |model| model['provider'] }).to all(eq('typesafe'))
    expect(models_data.map { |model| model['capabilities'] }).to all(eq(['structured_output']))
    expect(models_data.map { |model| model['id'] }).to include('jev-latest')
  end

  it 'merges the packaged catalog into the registry' do
    model = RubyLLM.models.find('jev-latest', provider: :typesafe)

    expect(model.provider).to eq('typesafe')
    expect(model.family).to eq('jev')
    expect(model.type).to eq(:chat)
    expect(model.supports?(:structured_output)).to be(true)
    expect(model.supports?(:streaming)).to be(false)
    expect(model.supports?(:function_calling)).to be(false)
    expect(model.supports?(:vision)).to be(false)
    expect(model.modalities.input).to eq(['text'])
    expect(model.modalities.output).to eq(['text'])
  end

  it 'resolves jev-latest without naming the provider' do
    expect(RubyLLM.models.find('jev-latest').provider).to eq('typesafe')
    expect(RubyLLM.chat(model: 'jev-latest').model.provider).to eq('typesafe')
  end

  it 'lists the catalog by provider' do
    ids = RubyLLM.models.by_provider(:typesafe).chat_models.map(&:id)

    expect(ids).to eq(models_data.map { |model| model['id'] })
  end

  it 'raises ModelNotFoundError for an unknown TypeSafe model unless it is assumed to exist' do
    expect { RubyLLM.chat(model: 'jev-9000', provider: :typesafe) }.to raise_error(RubyLLM::ModelNotFoundError)

    chat = RubyLLM.chat(model: 'jev-9000', provider: :typesafe, assume_model_exists: true)
    expect(chat.model.id).to eq('jev-9000')
  end
end
