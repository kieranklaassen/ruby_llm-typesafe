# frozen_string_literal: true

require 'spec_helper'

# Response fixtures are the examples published at https://docs.typesafe.ai/api.
RSpec.describe RubyLLM::Protocols::SystemOne::Chat do
  include_context 'with configured RubyLLM'

  let(:provider) { RubyLLM::Providers::TypeSafe.new(RubyLLM.config) }
  let(:model) { RubyLLM.models.find(model_for) }
  let(:protocol) { RubyLLM::Protocols::SystemOne.new(provider, model) }
  let(:schema) { typesafe_chat.schema }

  def render(messages, **options)
    protocol.send(:render_payload, messages, model: model, schema: schema, **options)
  end

  def user(content, attachments: [])
    RubyLLM::Message.new(role: :user, content: content, attachments: attachments)
  end

  describe '#completion_url' do
    it 'posts to the System One endpoint' do
      expect(protocol.send(:completion_url)).to eq('v1/systemone')
    end
  end

  describe '#render_payload' do
    it 'renders the model, the latest user message as state, and the question map' do
      expect(render([user(support_state)])).to eq(
        model: 'jev-latest',
        state: support_state,
        questions: support_questions
      )
    end

    it 'evaluates only the latest user turn' do
      messages = [
        RubyLLM::Message.new(role: :system, content: 'Ignored by System One'),
        user('First ticket'),
        RubyLLM::Message.new(role: :assistant, content: '{"is_urgent":{"type":"noul","noul":0.1}}'),
        user('Second ticket')
      ]

      expect(render(messages)[:state]).to eq('Second ticket')
    end

    it 'decodes JSON object and array content into structured state' do
      expect(render([user('{"ticket": {"subject": "Payouts failing"}}')])[:state])
        .to eq('ticket' => { 'subject' => 'Payouts failing' })
      expect(render([user('  ["a", "b"]')])[:state]).to eq(%w[a b])
    end

    it 'keeps JSON scalars and malformed JSON as string state' do
      expect(render([user('42')])[:state]).to eq('42')
      expect(render([user('true')])[:state]).to eq('true')
      expect(render([user('{not json')])[:state]).to eq('{not json')
      expect(render([user('[1, 2')])[:state]).to eq('[1, 2')
    end

    it 'prefers an explicit state over the user message' do
      payload = render([user('ignored')], state: { 'sender' => 'payroll@example.com' })

      expect(payload[:state]).to eq('sender' => 'payroll@example.com')
    end

    it 'requires state' do
      expect { render([]) }.to raise_error(RubyLLM::Error, /needs state to evaluate/)
      expect { render([user(nil)]) }.to raise_error(RubyLLM::Error, /needs state to evaluate/)
    end

    it 'rejects attachments' do
      audio = RubyLLM::Attachment.new(StringIO.new('RIFF....WAVEfmt '), filename: 'ruby.wav')

      expect { render([user('Transcribe this', attachments: [audio])]) }
        .to raise_error(RubyLLM::UnsupportedAttachmentError, %r{audio/wav})
    end

    it 'requires a TypeSafe schema' do
      plain = { name: 'person', schema: { type: 'object', properties: { name: { type: 'string' } } } }

      expect { protocol.send(:render_payload, [user('x')], model: model, schema: plain) }
        .to raise_error(RubyLLM::Error, /typed questions only/)
      expect { protocol.send(:render_payload, [user('x')], model: model, schema: nil) }
        .to raise_error(RubyLLM::Error, /typed questions only/)
    end
  end

  describe '.questions_in' do
    it 'reads questions from a normalized schema with Symbol or String keys' do
      expect(described_class.questions_in(schema)).to eq(support_questions)
      expect(described_class.questions_in(support_schema.to_json_schema)).to eq(support_questions)
    end

    it 'returns nil for schemas without questions' do
      expect(described_class.questions_in(nil)).to be_nil
      expect(described_class.questions_in({ type: 'object', properties: {} })).to be_nil
      expect(described_class.questions_in({ schema: { 'x-typesafe' => { questions: {} } } })).to be_nil
      expect(described_class.questions_in('string')).to be_nil
    end
  end

  describe '#parse_completion_body' do
    let(:raw) { instance_double(Faraday::Response, status: 200) }

    it 'returns the answers as an assistant message with model, usage, and raw response' do
      message = protocol.send(:parse_completion_body, success_body(model: 'jev-1.13.0'), raw: raw)

      expect(message.role).to eq(:assistant)
      expect(message.parsed).to eq(support_answers)
      expect(message.model).to eq('jev-1.13.0')
      expect(message.tokens.input).to eq(312)
      expect(message.tokens.output).to eq(48)
      expect(message.finish_reason).to eq(:stop)
      expect(message.raw).to be(raw)
      expect(message).to be_stopped
      expect(message).not_to be_tool_call
    end

    it 'keeps every documented answer field' do
      parsed = protocol.send(:parse_completion_body, success_body, raw: raw).parsed

      expect(parsed['is_urgent']).to eq('type' => 'noul', 'noul' => 0.92)
      expect(parsed['department']).to include('type' => 'choice', 'choice' => 'technical', 'confidence' => 0.82)
      expect(parsed['department']['probabilities'].values.sum).to be_within(0.001).of(1)
      expect(parsed['frustration']).to include('type' => 'score', 'score' => 1.6)
      expect(parsed['frustration']['legend']).to eq('0' => 'Calm', '1' => 'Frustrated', '2' => 'Very angry')
    end

    it 'rejects bodies missing the documented shape' do
      [nil, 'text', [], {}, { 'answers' => {} }, { 'model' => 'jev', 'answers' => [] },
       { 'model' => 'jev', 'answers' => {}, 'usage' => nil }].each do |body|
        expect { protocol.send(:parse_completion_body, body, raw: raw) }
          .to raise_error(RubyLLM::Error, /unexpected response body/)
      end
    end
  end
end
