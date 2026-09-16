# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::TypeSafe::Schema, '#choice' do
  def schema(&)
    described_class.new(&)
  end

  it 'renders the documented option map with string keys' do
    built = schema do |s|
      s.choice :department,
               instructions: 'Which team should handle this?',
               criteria: { billing: 'Payments, invoicing, refunds', 'technical' => 'Bugs, outages', sales: nil }
    end

    expect(built.questions['department']).to eq(
      'type' => 'choice',
      'instructions' => 'Which team should handle this?',
      'criteria' => { 'billing' => 'Payments, invoicing, refunds', 'technical' => 'Bugs, outages', 'sales' => nil }
    )
  end

  it 'accepts structured option descriptions and a taxonomy of subtrees' do
    built = schema do |s|
      s.choice :department, instructions: { question: 'Which team?', focus: 'Primary request only' },
                            criteria: { billing: { what: 'Charges', not_for: 'Tracking', examples: ['Charged twice'] },
                                        'Sporting Goods' => { Cycling: ['Bike Bottles', 'Helmets'] } }
    end

    expect(built.questions['department']['criteria']).to eq(
      'billing' => { 'what' => 'Charges', 'not_for' => 'Tracking', 'examples' => ['Charged twice'] },
      'Sporting Goods' => { 'Cycling' => ['Bike Bottles', 'Helmets'] }
    )
  end

  it 'requires a non-empty Hash of options' do
    expect { schema { |s| s.choice :a, instructions: 'x', criteria: {} } }
      .to raise_error(ArgumentError, /non-empty Hash/)
    expect { schema { |s| s.choice :a, instructions: 'x', criteria: %w[a b] } }
      .to raise_error(ArgumentError, /non-empty Hash/)
    expect { schema { |s| s.choice :a, instructions: 'x', criteria: nil } }
      .to raise_error(ArgumentError, /non-empty Hash/)
  end

  it 'requires option keys to be non-empty Strings or Symbols' do
    expect { schema { |s| s.choice :a, instructions: 'x', criteria: { '' => 'x' } } }
      .to raise_error(ArgumentError, /choice option keys must be non-empty/)
    expect { schema { |s| s.choice :a, instructions: 'x', criteria: { 1 => 'x' } } }
      .to raise_error(ArgumentError, /choice option keys must be non-empty/)
  end

  it 'requires option descriptions to be JSON-compatible' do
    expect { schema { |s| s.choice :a, instructions: 'x', criteria: { b: :symbol } } }
      .to raise_error(ArgumentError, /choice option contains Symbol/)
    expect { schema { |s| s.choice :a, instructions: 'x', criteria: { b: Float::NAN } } }
      .to raise_error(ArgumentError, /non-finite/)
  end

  it 'describes the answer as the chosen option, a distribution, and confidence' do
    built = schema do |s|
      s.choice :department, instructions: 'x', criteria: { billing: nil, technical: nil, sales: nil }
    end
    answer = built.to_json_schema['schema']['properties']['department']
    probability = { 'type' => 'number', 'minimum' => 0, 'maximum' => 1 }

    expect(answer['required']).to eq(%w[type choice probabilities confidence])
    expect(answer['properties']['type']).to eq('const' => 'choice')
    expect(answer['properties']['choice']).to eq('type' => 'string', 'enum' => %w[billing technical sales])
    expect(answer['properties']['probabilities']).to eq(
      'type' => 'object',
      'properties' => { 'billing' => probability, 'technical' => probability, 'sales' => probability },
      'required' => %w[billing technical sales]
    )
    expect(answer['properties']['confidence']).to eq(probability)
  end
end
