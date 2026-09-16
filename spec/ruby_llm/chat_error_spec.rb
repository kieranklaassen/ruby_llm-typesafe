# frozen_string_literal: true

require 'spec_helper'

RSpec::Matchers.define :look_like_json do
  match do |actual|
    actual.strip.start_with?('{', '[')
  end

  failure_message do |actual|
    "expected '#{actual}' to look like JSON"
  end

  failure_message_when_negated do |actual|
    "expected '#{actual}' not to look like JSON"
  end
end

RSpec.describe RubyLLM::Chat, :live do
  include_context 'with configured RubyLLM'

  each_model(STRUCTURED_OUTPUT_MODELS) do |provider, model|
    context "with #{provider}/#{model}" do
      let(:chat) { RubyLLM.chat(model: model, provider: provider).with_schema(support_schema) }

      it 'raises appropriate auth error' do
        RubyLLM.config.typesafe_api_key = 'invalid-key'

        expect { chat.ask(support_state) }.to raise_error(RubyLLM::UnauthorizedError) do |error|
          expect(error.response.status).to eq(401)
          expect(error.message).not_to be_empty
          expect(error.message).not_to look_like_json
          expect(error.message).to match(/^[A-Za-z]/)
        end
      end

      it 'raises a readable validation error for a malformed question' do
        chat.with_provider_options(questions: { bogus: { type: 'nope' } })

        expect { chat.ask(support_state) }.to raise_error(RubyLLM::Error) do |error|
          expect(error.response.status).to eq(422)
          expect(error.message).to start_with('questions.bogus: ')
          expect(error.message).not_to look_like_json
        end
      end

      it 'raises a BadRequestError for an unknown model' do
        chat.with_provider_options(model: 'no-such-model')

        expect { chat.ask(support_state) }.to raise_error(RubyLLM::BadRequestError) do |error|
          expect(error.response.status).to eq(400)
          expect(error.message).to include('no-such-model')
          expect(error.message).not_to look_like_json
        end
      end
    end
  end
end
