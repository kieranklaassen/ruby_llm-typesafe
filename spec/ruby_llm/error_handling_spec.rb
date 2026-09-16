# frozen_string_literal: true

require 'spec_helper'

# Status codes and body shapes follow https://docs.typesafe.ai/api#errors.
RSpec.describe 'TypeSafe error handling' do # rubocop:disable RSpec/DescribeClass
  include_context 'with configured RubyLLM'

  def error_response(status, body, headers: {})
    json_response(body, status: status, headers: headers)
  end

  it 'raises UnauthorizedError for 401 with the service message' do
    stub_systemone(error_response(401, { 'detail' => { 'error_type' => 'authentication_error',
                                                       'message' => 'Invalid API key' } }))

    expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::UnauthorizedError) do |error|
      expect(error.message).to eq('Invalid API key')
      expect(error.response.status).to eq(401)
      expect(error.message).not_to include(RubyLLM.config.typesafe_api_key)
    end
  end

  it 'raises BadRequestError for 400 API usage errors' do
    stub_systemone(error_response(400, { 'detail' => { 'error_type' => 'api_usage_error',
                                                       'message' => 'Unknown model: no-such-model' } }))

    expect { typesafe_chat.ask(support_state) }
      .to raise_error(RubyLLM::BadRequestError, 'Unknown model: no-such-model')
  end

  it 'raises a readable RubyLLM::Error for 422 validation failures' do
    stub_systemone(error_response(422, { 'detail' => [{ 'type' => 'missing', 'loc' => %w[body state],
                                                        'msg' => 'Field required' }] }))

    expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::Error) do |error|
      expect(error.message).to eq('state: Field required')
      expect(error.response.status).to eq(422)
    end
  end

  it 'raises RateLimitError for 429' do
    stub_systemone(error_response(429, { 'detail' => { 'message' => 'Rate limit exceeded' } }))

    expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::RateLimitError, 'Rate limit exceeded')
  end

  it 'raises OverloadedError for 529' do
    stub_systemone(error_response(529, { 'detail' => { 'message' => 'Overloaded' } }))

    expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::OverloadedError, 'Overloaded')
  end

  it 'raises ServerError for 500 and ServiceUnavailableError for 503' do
    stub_systemone(error_response(500, { 'detail' => { 'message' => 'Boom' } }))
    expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::ServerError, 'Boom')

    WebMock.reset!
    stub_systemone(error_response(503, { 'detail' => { 'message' => 'Down' } }))
    expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::ServiceUnavailableError, 'Down')
  end

  it 'keeps the error readable when the body is not JSON' do
    stub_systemone({ status: 502, body: '<html>Bad Gateway</html>', headers: { 'Content-Type' => 'text/html' } })

    expect { typesafe_chat.ask(support_state) }
      .to raise_error(RubyLLM::ServiceUnavailableError, '<html>Bad Gateway</html>')
  end

  describe 'retries' do
    before do
      RubyLLM.config.max_retries = 2
      allow_any_instance_of(Faraday::Retry::Middleware).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
    end

    it 'retries a 529 and returns the answers once TypeSafe recovers' do
      stub_systemone(error_response(529, { 'detail' => { 'message' => 'Overloaded' } }), json_response(success_body))

      message = typesafe_chat.ask(support_state)

      expect(message.parsed).to eq(support_answers)
      expect(systemone_requests.size).to eq(2)
    end

    it 'honors Retry-After on a 429 before retrying' do
      rate_limited = error_response(429, { 'detail' => { 'message' => 'Slow down' } },
                                    headers: { 'Retry-After' => '3' })
      stub_systemone(rate_limited, json_response(success_body))

      expect_any_instance_of(Faraday::Retry::Middleware).to receive(:sleep).with(3.0) # rubocop:disable RSpec/AnyInstance

      typesafe_chat.ask(support_state)
      expect(systemone_requests.size).to eq(2)
    end

    it 'raises the final error once retries are exhausted' do
      stub_systemone(*Array.new(3) { error_response(529, { 'detail' => { 'message' => 'Still overloaded' } }) })

      expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::OverloadedError, 'Still overloaded')
      expect(systemone_requests.size).to eq(3)
    end

    it 'does not retry validation or authentication failures' do
      stub_systemone(error_response(401, { 'detail' => { 'message' => 'Invalid API key' } }))

      expect { typesafe_chat.ask(support_state) }.to raise_error(RubyLLM::UnauthorizedError)
      expect(systemone_requests.size).to eq(1)
    end
  end
end
