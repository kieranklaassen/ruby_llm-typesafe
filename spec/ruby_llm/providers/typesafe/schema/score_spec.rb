# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::TypeSafe::Schema, '#score' do
  def schema(&)
    described_class.new(&)
  end

  it 'renders the documented ordered levels' do
    built = schema do |s|
      s.score :frustration, instructions: 'How frustrated is the customer?',
                            criteria: ['Calm', 'Frustrated', 'Very angry']
    end

    expect(built.questions['frustration']).to eq(
      'type' => 'score',
      'instructions' => 'How frustrated is the customer?',
      'criteria' => ['Calm', 'Frustrated', 'Very angry']
    )
  end

  it 'preserves level order and accepts structured levels' do
    built = schema do |s|
      s.score :pr_scope, instructions: { question: 'How focused is this pull request?', note: 'Count changes' },
                         criteria: [{ summary: 'One change', signals: ['A single fix'] }, 'Several changes', nil]
    end

    expect(built.questions['pr_scope']['criteria']).to eq(
      [{ 'summary' => 'One change', 'signals' => ['A single fix'] }, 'Several changes', nil]
    )
    expect(schema do |s|
      s.score :a, instructions: 'x', criteria: %w[c b a]
    end.questions['a']['criteria']).to eq(%w[c b a])
  end

  it 'requires an Array of at least two levels' do
    expect { schema { |s| s.score :a, instructions: 'x', criteria: ['only'] } }
      .to raise_error(ArgumentError, /at least two ordered levels/)
    expect { schema { |s| s.score :a, instructions: 'x', criteria: [] } }
      .to raise_error(ArgumentError, /at least two ordered levels/)
    expect { schema { |s| s.score :a, instructions: 'x', criteria: { low: 1, high: 2 } } }
      .to raise_error(ArgumentError, /at least two ordered levels/)
  end

  it 'requires level descriptions to be JSON-compatible' do
    expect { schema { |s| s.score :a, instructions: 'x', criteria: [Object.new, 'b'] } }
      .to raise_error(ArgumentError, /score level contains Object/)
    expect { schema { |s| s.score :a, instructions: 'x', criteria: [{ 'ok' => :symbol }, 'b'] } }
      .to raise_error(ArgumentError, /score level contains Symbol/)
  end

  it 'describes the answer as a weighted score, legend, distribution, and confidence' do
    built = schema { |s| s.score :frustration, instructions: 'x', criteria: %w[Calm Frustrated Angry] }
    answer = built.to_json_schema['schema']['properties']['frustration']
    probability = { 'type' => 'number', 'minimum' => 0, 'maximum' => 1 }

    expect(answer['required']).to eq(%w[type score legend probabilities confidence])
    expect(answer['properties']['type']).to eq('const' => 'score')
    expect(answer['properties']['score']).to eq('type' => 'number', 'minimum' => 0, 'maximum' => 2)
    expect(answer['properties']['legend']).to eq(
      'type' => 'object', 'properties' => { '0' => {}, '1' => {}, '2' => {} }, 'required' => %w[0 1 2]
    )
    expect(answer['properties']['probabilities']).to eq(
      'type' => 'object',
      'properties' => { '0' => probability, '1' => probability, '2' => probability },
      'required' => %w[0 1 2]
    )
    expect(answer['properties']['confidence']).to eq(probability)
  end
end
