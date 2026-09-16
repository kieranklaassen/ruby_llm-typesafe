# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::TypeSafe::Schema do
  include_context 'with configured RubyLLM'

  describe '#initialize' do
    it 'yields itself and keeps questions in insertion order' do
      expect(support_schema.questions).to eq(support_questions)
      expect(support_schema.ids).to eq(%w[is_urgent department frustration])
      expect(support_schema.size).to eq(3)
      expect(support_schema).not_to be_empty
    end

    it 'starts empty without a block' do
      schema = described_class.new

      expect(schema).to be_empty
      expect(schema.size).to eq(0)
      expect(schema.ids).to eq([])
    end

    it 'returns self from each question method for chaining' do
      schema = described_class.new

      expect(schema.noul(:a, instructions: 'A?')).to be(schema)
      expect(schema.choice(:b, instructions: 'B?', criteria: { x: nil })).to be(schema)
      expect(schema.score(:c, instructions: 'C?', criteria: %w[low high])).to be(schema)
      expect(schema.ids).to eq(%w[a b c])
    end
  end

  describe 'question ids' do
    it 'accepts Symbols and Strings of letters, digits, underscores, dots, and hyphens' do
      schema = described_class.new do |s|
        s.noul :snake_case, instructions: 'x'
        s.noul 'kebab-case.v2', instructions: 'x'
      end

      expect(schema.ids).to eq(%w[snake_case kebab-case.v2])
    end

    it 'rejects empty, unsafe, and non-String ids' do
      expect { described_class.new { |s| s.noul '', instructions: 'x' } }
        .to raise_error(ArgumentError, /question id ""/)
      expect { described_class.new { |s| s.noul 'has space', instructions: 'x' } }
        .to raise_error(ArgumentError, /letters, digits/)
      expect { described_class.new { |s| s.noul 42, instructions: 'x' } }
        .to raise_error(ArgumentError, /String or Symbol/)
    end

    it 'rejects duplicate ids across Symbol and String spellings' do
      expect do
        described_class.new do |s|
          s.noul :dup, instructions: 'x'
          s.choice 'dup', instructions: 'y', criteria: { a: nil }
        end
      end.to raise_error(ArgumentError, /"dup" is already defined/)
    end
  end

  describe 'instructions' do
    it 'accepts strings, objects, and arrays' do
      schema = described_class.new do |s|
        s.noul :text, instructions: 'Plain text'
        s.noul :object, instructions: { question: 'Credential request?', compare: %w[a b] }
        s.noul :array, instructions: ['Check the sender', 'Check the domain']
      end

      expect(schema.questions['object']['instructions']).to eq('question' => 'Credential request?',
                                                               'compare' => %w[
                                                                 a b
                                                               ])
      expect(schema.questions['array']['instructions']).to eq(['Check the sender', 'Check the domain'])
    end

    it 'are required' do
      expect { described_class.new { |s| s.noul :a, instructions: nil } }
        .to raise_error(ArgumentError, /instructions are required/)
      expect { described_class.new { |s| s.noul :a, instructions: '' } }
        .to raise_error(ArgumentError, /instructions are required/)
    end

    it 'must be JSON-compatible' do
      expect { described_class.new { |s| s.noul :a, instructions: Float::NAN } }
        .to raise_error(ArgumentError, /non-finite/)
      expect { described_class.new { |s| s.noul :a, instructions: Float::INFINITY } }
        .to raise_error(ArgumentError, /non-finite/)
      expect { described_class.new { |s| s.noul :a, instructions: :symbol } }
        .to raise_error(ArgumentError, /Symbol, which is not JSON-compatible/)
      expect { described_class.new { |s| s.noul :a, instructions: { 1 => 'x' } } }
        .to raise_error(ArgumentError, /non-empty Strings or Symbols/)
      expect { described_class.new { |s| s.noul :a, instructions: [Object.new] } }
        .to raise_error(ArgumentError, /Object, which is not JSON-compatible/)
    end
  end

  describe 'caller data' do
    it 'is copied, not shared or mutated' do
      instructions = { 'question' => 'Which team?' }
      criteria = { 'billing' => ['Charges'] }
      schema = described_class.new { |s| s.choice 'department', instructions: instructions, criteria: criteria }

      schema.questions['department']['criteria']['billing'] << 'mutated'
      instructions['question'] = 'changed'

      expect(criteria).to eq('billing' => ['Charges'])
      expect(schema.questions['department']['instructions']).to eq('question' => 'Which team?')
    end
  end

  describe '#to_json_schema' do
    let(:json_schema) { support_schema.to_json_schema }
    let(:definition) { json_schema['schema'] }

    it 'names the schema and describes the answer map' do
      expect(json_schema['name']).to eq('typesafe_answers')
      expect(json_schema['description']).to include('TypeSafe System One answers')
      expect(definition['type']).to eq('object')
      expect(definition['required']).to eq(%w[is_urgent department frustration])
      expect(definition['properties'].keys).to eq(%w[is_urgent department frustration])
    end

    it 'carries the question map under the x-typesafe extension' do
      expect(definition['x-typesafe']).to eq('questions' => support_questions)
    end

    it 'refuses to describe an empty schema' do
      expect { described_class.new.to_json_schema }.to raise_error(ArgumentError, /no questions/)
    end

    it 'is also available as to_h and to_json' do
      expect(support_schema.to_h).to eq(json_schema)
      expect(JSON.parse(support_schema.to_json)).to eq(json_schema)
    end

    it 'survives Chat#with_schema normalization' do
      chat = typesafe_chat

      expect(chat.schema[:name]).to eq('typesafe_answers')
      expect(chat.schema[:schema][:required]).to eq(%w[is_urgent department frustration])
      expect(RubyLLM::Protocols::SystemOne::Chat.questions_in(chat.schema)).to eq(support_questions)
    end
  end
end
