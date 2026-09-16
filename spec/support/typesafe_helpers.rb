# frozen_string_literal: true

require 'json'

# Documented System One request and response shapes from
# https://docs.typesafe.ai/api, plus helpers for stubbing the endpoint in
# unit specs.
module TypesafeHelpers
  ENDPOINT = 'https://api.typesafe.ai/v1/systemone'

  def noul_answer
    { 'type' => 'noul', 'noul' => 0.92 }
  end

  def choice_answer
    {
      'type' => 'choice',
      'choice' => 'technical',
      'probabilities' => { 'billing' => 0.08, 'technical' => 0.85, 'sales' => 0.07 },
      'confidence' => 0.82
    }
  end

  def score_answer
    {
      'type' => 'score',
      'score' => 1.6,
      'legend' => { '0' => 'Calm', '1' => 'Frustrated', '2' => 'Very angry' },
      'probabilities' => { '0' => 0.05, '1' => 0.3, '2' => 0.65 },
      'confidence' => 0.78
    }
  end

  def support_answers
    { 'is_urgent' => noul_answer, 'department' => choice_answer, 'frustration' => score_answer }
  end

  def support_usage
    { 'input_tokens' => 312, 'output_tokens' => 48 }
  end

  # The support ticket example from the TypeSafe API reference, one question
  # of each type over one state.
  def support_schema
    RubyLLM::Providers::TypeSafe::Schema.new do |s|
      s.noul :is_urgent, instructions: 'Does this convey urgency?',
                         criteria: { true => 'Explicitly time-sensitive', false => 'No urgency expressed' }
      s.choice :department, instructions: 'Which team should handle this?',
                            criteria: { billing: 'Payments, invoicing, refunds',
                                        technical: 'Bugs, outages, integrations',
                                        sales: 'Pricing, upgrades, new accounts' }
      s.score :frustration, instructions: 'How frustrated is the customer?',
                            criteria: ['Calm', 'Frustrated', 'Very angry']
    end
  end

  def support_questions
    {
      'is_urgent' => {
        'type' => 'noul',
        'instructions' => 'Does this convey urgency?',
        'criteria' => { 'true' => 'Explicitly time-sensitive', 'false' => 'No urgency expressed' }
      },
      'department' => {
        'type' => 'choice',
        'instructions' => 'Which team should handle this?',
        'criteria' => { 'billing' => 'Payments, invoicing, refunds',
                        'technical' => 'Bugs, outages, integrations',
                        'sales' => 'Pricing, upgrades, new accounts' }
      },
      'frustration' => {
        'type' => 'score',
        'instructions' => 'How frustrated is the customer?',
        'criteria' => ['Calm', 'Frustrated', 'Very angry']
      }
    }
  end

  def support_state
    'Help! My payouts have been failing for 3 days.'
  end

  def success_body(model: 'jev-latest', answers: support_answers, usage: support_usage)
    { 'model' => model, 'answers' => answers, 'usage' => usage }
  end

  def json_response(body, status: 200, headers: {})
    { status: status, body: JSON.generate(body), headers: { 'Content-Type' => 'application/json' }.merge(headers) }
  end

  # Stubs the evaluation endpoint with +responses+ in order and records every
  # request so specs can assert on the exact wire payload.
  def stub_systemone(*responses, url: ENDPOINT)
    queue = responses.empty? ? [json_response(success_body)] : responses.dup
    stub_request(:post, url).to_return do |request|
      systemone_requests << request
      queue.size > 1 ? queue.shift : queue.first
    end
  end

  def systemone_requests
    @systemone_requests ||= []
  end

  def last_request_body
    JSON.parse(systemone_requests.fetch(-1).body)
  end

  def typesafe_chat(model: model_for, schema: support_schema)
    chat = RubyLLM.chat(model: model, provider: :typesafe)
    schema ? chat.with_schema(schema) : chat
  end
end

RSpec.configure do |config|
  config.include TypesafeHelpers
end
