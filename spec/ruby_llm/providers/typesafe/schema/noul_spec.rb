# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::TypeSafe::Schema, '#noul' do
  def schema(&)
    described_class.new(&)
  end

  it 'renders the documented question without criteria' do
    built = schema { |s| s.noul :is_urgent, instructions: 'Does this convey urgency?' }

    expect(built.questions['is_urgent']).to eq('type' => 'noul', 'instructions' => 'Does this convey urgency?')
  end

  it 'renders true and false criteria from Symbol, String, or boolean keys' do
    built = schema do |s|
      s.noul :symbols, instructions: 'x', criteria: %i[true false].zip(%w[Yes No]).to_h
      s.noul :strings, instructions: 'x', criteria: { 'true' => 'Yes', 'false' => 'No' }
      s.noul :booleans, instructions: 'x', criteria: { true => 'Yes', false => 'No' }
      s.noul :partial, instructions: 'x', criteria: { true => 'Only the yes side' }
    end

    expect(built.questions['symbols']['criteria']).to eq('true' => 'Yes', 'false' => 'No')
    expect(built.questions['strings']['criteria']).to eq('true' => 'Yes', 'false' => 'No')
    expect(built.questions['booleans']['criteria']).to eq('true' => 'Yes', 'false' => 'No')
    expect(built.questions['partial']['criteria']).to eq('true' => 'Only the yes side')
  end

  it 'accepts structured true and false descriptions' do
    built = schema do |s|
      s.noul :requests_credentials,
             instructions: { question: 'Does the message ask for a credential?' },
             criteria: { true => { what: 'Asks for a password', examples: ['Reply with your password'] }, false => nil }
    end

    expect(built.questions['requests_credentials']['criteria']).to eq(
      'true' => { 'what' => 'Asks for a password', 'examples' => ['Reply with your password'] },
      'false' => nil
    )
  end

  it 'rejects criteria that are not a Hash of true and false' do
    expect { schema { |s| s.noul :a, instructions: 'x', criteria: 'yes' } }
      .to raise_error(ArgumentError, /Hash with only true and false keys/)
    expect { schema { |s| s.noul :a, instructions: 'x', criteria: { maybe: '?' } } }
      .to raise_error(ArgumentError, /:maybe must be true or false/)
    expect { schema { |s| s.noul :a, instructions: 'x', criteria: { true => :symbol } } }
      .to raise_error(ArgumentError, /Symbol, which is not JSON-compatible/)
  end

  it 'describes the answer as a probability of yes' do
    answer = schema { |s| s.noul :is_urgent, instructions: 'x' }.to_json_schema['schema']['properties']['is_urgent']

    expect(answer).to eq(
      'type' => 'object',
      'properties' => {
        'type' => { 'const' => 'noul' },
        'noul' => { 'type' => 'number', 'minimum' => 0, 'maximum' => 1 }
      },
      'required' => %w[type noul]
    )
  end
end
