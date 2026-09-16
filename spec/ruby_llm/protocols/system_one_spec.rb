# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Protocols::SystemOne do
  include_context 'with configured RubyLLM'

  describe 'the requests it sends' do
    it 'posts the documented payload with JSON content and a Bearer token' do
      stub_systemone

      typesafe_chat.ask(support_state)

      request = systemone_requests.fetch(0)
      expect(request.uri.host).to eq('api.typesafe.ai')
      expect(request.uri.path).to eq('/v1/systemone')
      expect(request.headers['Content-Type']).to eq('application/json')
      expect(request.headers['Authorization']).to eq("Bearer #{RubyLLM.config.typesafe_api_key}")
      expect(last_request_body).to eq(
        'model' => 'jev-latest',
        'state' => support_state,
        'questions' => support_questions
      )
    end

    it 'sends the requested model id, including one assumed to exist' do
      stub_systemone

      RubyLLM.chat(model: 'jev-preview', provider: :typesafe).with_schema(support_schema).ask(support_state)
      RubyLLM.chat(model: 'jev-2', provider: :typesafe, assume_model_exists: true)
             .with_schema(support_schema).ask(support_state)

      expect(systemone_requests.map { |request| JSON.parse(request.body)['model'] }).to eq(%w[jev-preview jev-2])
    end

    it 'honors a custom API base' do
      RubyLLM.config.typesafe_api_base = 'https://typesafe.example.com/proxy'
      stub_systemone(url: 'https://typesafe.example.com/proxy/v1/systemone')

      typesafe_chat.ask(support_state)

      expect(systemone_requests.size).to eq(1)
    ensure
      RubyLLM.config.typesafe_api_base = nil
    end

    it 'sends structured state when the message is a JSON object' do
      stub_systemone
      ticket = { 'ticket' => { 'subject' => 'Payouts failing', 'messages' => [{ 'text' => support_state }] } }

      typesafe_chat.ask(JSON.generate(ticket))

      expect(last_request_body['state']).to eq(ticket)
    end

    it 'takes explicit state from with_provider_options and merges other options into the payload' do
      stub_systemone

      typesafe_chat.with_provider_options(state: %w[a b], extra: { flag: true }).ask('ignored text')

      expect(last_request_body['state']).to eq(%w[a b])
      expect(last_request_body['extra']).to eq('flag' => true)
    end

    it 'evaluates each ask independently, sending only the latest state' do
      stub_systemone(json_response(success_body), json_response(success_body(answers: { 'is_urgent' => noul_answer })))
      chat = typesafe_chat

      chat.ask('First ticket')
      second = chat.ask('Second ticket')

      expect(systemone_requests.map do |request|
        JSON.parse(request.body)['state']
      end).to eq(['First ticket', 'Second ticket'])
      expect(last_request_body).not_to include('messages')
      expect(second.parsed).to eq('is_urgent' => noul_answer)
      expect(chat.messages.map(&:role)).to eq(%i[user assistant user assistant])
    end

    it 'merges caller headers without replacing authorization' do
      stub_systemone

      typesafe_chat.with_headers('X-Trace' => 'abc').ask(support_state)

      request = systemone_requests.fetch(0)
      expect(request.headers['X-Trace']).to eq('abc')
      expect(request.headers['Authorization']).to eq("Bearer #{RubyLLM.config.typesafe_api_key}")
    end

    it 'renders the payload without a request through Chat#render' do
      payload = typesafe_chat.ask_later(support_state).render

      expect(payload).to eq(model: 'jev-latest', state: support_state, questions: support_questions)
      expect(systemone_requests).to be_empty
    end
  end

  describe 'the responses it returns' do
    it 'returns the answers as a parsed assistant message with model, usage, and raw response' do
      stub_systemone(json_response(success_body(model: 'jev-1.13.0')))

      message = typesafe_chat.ask(support_state)

      expect(message).to be_a(RubyLLM::Message)
      expect(message.role).to eq(:assistant)
      expect(message.content).to eq(JSON.generate(support_answers))
      expect(message.parsed).to eq(support_answers)
      expect(message.model).to eq('jev-1.13.0')
      expect(message.tokens.input).to eq(312)
      expect(message.tokens.output).to eq(48)
      expect(message.raw.status).to eq(200)
      expect(message.raw.body).to eq(success_body(model: 'jev-1.13.0'))
      expect(message.raw.env.request_body).to include('"questions"')
    end

    it 'raises on a 2xx body without the documented shape' do
      stub_systemone(json_response({ 'model' => 'jev-latest', 'result' => 'nope' }))

      expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::Error, /unexpected response body/)
    end

    it 'raises on an empty 2xx body' do
      stub_systemone({ status: 200, body: '', headers: { 'Content-Type' => 'application/json' } })

      expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::Error, /empty response body/)
    end
  end

  describe 'structured output only' do
    it 'refuses a plain ask before touching the network' do
      expect { typesafe_chat(schema: nil).ask('Hello') }.to raise_error(RubyLLM::Error, /typed questions only/)
      expect(WebMock).not_to have_requested(:post, TypesafeHelpers::ENDPOINT)
    end

    it 'refuses an ordinary JSON Schema' do
      person = { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] }

      expect do
        typesafe_chat(schema: person).ask('Generate a person')
      end.to raise_error(RubyLLM::Error, /typed questions only/)
    end

    it 'refuses to stream' do
      expect { typesafe_chat.ask(support_state) { |chunk| chunk } }
        .to raise_error(RubyLLM::Error, "TypeSafe doesn't support streaming")
    end

    it 'refuses tools' do
      weather = Class.new(RubyLLM::Tool) do
        def self.name = 'Weather'
        description 'Looks up the weather'
        def execute = 'Sunny'
      end

      expect { typesafe_chat.with_tools(weather).ask(support_state) }
        .to raise_error(RubyLLM::Error, "TypeSafe doesn't support tools")
    end

    it 'refuses server tools' do
      expect { typesafe_chat.with_server_tools(:web_search).ask(support_state) }
        .to raise_error(RubyLLM::UnsupportedServerToolError)
    end

    it 'refuses attachments' do
      audio = RubyLLM::Attachment.new(StringIO.new('RIFF....WAVEfmt '), filename: 'ruby.wav')

      expect { typesafe_chat.ask(support_state, with: audio) }.to raise_error(RubyLLM::UnsupportedAttachmentError)
    end

    it 'does not offer embeddings, images, or other operations' do
      expect { RubyLLM.embed('text', model: 'jev-latest', provider: :typesafe, assume_model_exists: true) }
        .to raise_error(RubyLLM::Error, /doesn't support embeddings/)
    end
  end
end
