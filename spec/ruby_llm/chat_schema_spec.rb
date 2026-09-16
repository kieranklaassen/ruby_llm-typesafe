# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Chat, :live do
  include_context 'with configured RubyLLM'

  def chat_for(provider, model, schema = support_schema)
    RubyLLM.chat(model: model, provider: provider).with_schema(schema)
  end

  def expect_probability(value)
    expect(value).to be_a(Numeric)
    expect(value).to be_between(0, 1)
  end

  each_model(STRUCTURED_OUTPUT_MODELS) do |provider, model|
    it "#{provider}/#{model} answers noul, choice, and score questions in one request" do
      response = chat_for(provider, model).ask(support_state)

      expect(response.content).to be_a(String)
      expect(response.role).to eq(:assistant)
      expect(response.model).to start_with('jev')
      expect(response.tokens.input.to_i).to be_positive
      expect(response.tokens.output.to_i).to be_positive
      expect(response).to be_stopped

      answers = response.parsed
      expect(answers.keys).to contain_exactly('is_urgent', 'department', 'frustration')

      expect(answers['is_urgent']['type']).to eq('noul')
      expect_probability(answers['is_urgent']['noul'])

      choice = answers['department']
      expect(choice['type']).to eq('choice')
      expect(choice['choice']).to(satisfy { |option| %w[billing technical sales].include?(option) })
      expect(choice['probabilities'].keys).to contain_exactly('billing', 'technical', 'sales')
      expect(choice['probabilities'].values.sum).to be_within(0.02).of(1)
      expect_probability(choice['confidence'])

      score = answers['frustration']
      expect(score['type']).to eq('score')
      expect(score['score']).to be_between(0, 2)
      expect(score['legend']).to eq('0' => 'Calm', '1' => 'Frustrated', '2' => 'Very angry')
      expect(score['probabilities'].keys).to contain_exactly('0', '1', '2')
      expect_probability(score['confidence'])
    end

    it "#{provider}/#{model} answers a single noul question" do
      schema = RubyLLM::Providers::TypeSafe::Schema.new do |s|
        s.noul :is_urgent, instructions: 'Does this convey urgency?',
                           criteria: { true => 'Explicitly time-sensitive', false => 'No urgency expressed' }
      end

      urgent = chat_for(provider, model, schema).ask(support_state).parsed['is_urgent']
      calm = chat_for(provider, model, schema).ask('Thanks, everything works now. No rush at all.').parsed['is_urgent']

      expect(urgent['type']).to eq('noul')
      expect_probability(urgent['noul'])
      expect_probability(calm['noul'])
      expect(urgent['noul']).to be > calm['noul']
    end

    it "#{provider}/#{model} answers a single choice question with structured options" do
      schema = RubyLLM::Providers::TypeSafe::Schema.new do |s|
        s.choice :department,
                 instructions: { question: 'Which team should handle this message?',
                                 focus: "Classify the customer's primary request." },
                 criteria: {
                   billing: { what: 'Charges, invoices, refunds', examples: ['I was charged twice'] },
                   orders: { what: 'Order status, delivery, returns', examples: ['Where is my package?'] },
                   account: nil
                 }
      end

      answer = chat_for(provider, model, schema).ask('Where is my package? Tracking has said label created for a week.')
                                                .parsed['department']

      expect(answer['type']).to eq('choice')
      expect(answer['choice']).to eq('orders')
      expect(answer['probabilities'].keys).to contain_exactly('billing', 'orders', 'account')
      expect_probability(answer['confidence'])
    end

    it "#{provider}/#{model} answers a single score question with structured levels" do
      schema = RubyLLM::Providers::TypeSafe::Schema.new do |s|
        s.score :pr_scope, instructions: 'How focused is this pull request description on a single change?',
                           criteria: [{ summary: 'One change, clearly stated' },
                                      { summary: 'One main change plus a small related tweak' },
                                      { summary: 'Several independent changes bundled together' }]
      end

      answer = chat_for(provider, model, schema)
               .ask('Fixed the null check. Also refactored the retry loop and bumped the SDK while I was in there.')
               .parsed['pr_scope']

      expect(answer['type']).to eq('score')
      expect(answer['score']).to be_between(0, 2)
      expect(answer['score']).to be > 1
      expect(answer['legend']['0']).to eq('summary' => 'One change, clearly stated')
      expect(answer['probabilities'].keys).to contain_exactly('0', '1', '2')
      expect_probability(answer['confidence'])
    end

    it "#{provider}/#{model} evaluates structured state from a JSON message" do
      schema = RubyLLM::Providers::TypeSafe::Schema.new do |s|
        s.noul :requests_credentials,
               instructions: { question: 'Does the `message` ask the recipient to disclose a sensitive credential?',
                               inspect: 'message' },
               criteria: { true => 'Asks the recipient to reply with a password, PIN, or one-time code',
                           false => 'No sensitive credential is requested' }
      end
      state = {
        sender: { display_name: 'Beaver Dam Builders Ltd.', email: 'donotreply@payroll.example' },
        message: 'Your Q3 bonus is ready. Reply with your login password so we can release the funds.'
      }

      response = chat_for(provider, model, schema).ask(JSON.generate(state))

      expect(JSON.parse(response.raw.env.request_body)['state']).to eq(JSON.parse(JSON.generate(state)))
      expect(response.parsed['requests_credentials']['noul']).to be > 0.5
    end

    it "#{provider}/#{model} evaluates explicit state from with_provider_options" do
      chat = chat_for(provider, model).with_provider_options(state: { ticket: support_state, channel: 'email' })

      response = chat.generate

      expect(JSON.parse(response.raw.env.request_body)['state']).to eq('ticket' => support_state, 'channel' => 'email')
      expect(response.parsed.keys).to contain_exactly('is_urgent', 'department', 'frustration')
    end

    it "#{provider}/#{model} treats each ask as an independent evaluation" do
      chat = chat_for(provider, model)

      first = chat.ask(support_state)
      second = chat.ask('Thanks, all good now.')

      expect(JSON.parse(second.raw.env.request_body)['state']).to eq('Thanks, all good now.')
      expect(first.parsed['is_urgent']['noul']).to be > second.parsed['is_urgent']['noul']
      expect(chat.messages.size).to eq(4)
    end

    it "#{provider}/#{model} returns the raw response" do
      response = chat_for(provider, model).ask(support_state)

      expect(response.raw.status).to eq(200)
      expect(response.raw.headers).not_to be_empty
      expect(response.raw.body).to include('model', 'answers', 'usage')
      expect(response.raw.env.request_body).not_to be_empty
    end
  end
end
