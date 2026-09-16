# ruby_llm-typesafe

[![CI](https://github.com/kieranklaassen/ruby_llm-typesafe/actions/workflows/ci.yml/badge.svg)](https://github.com/kieranklaassen/ruby_llm-typesafe/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/ruby_llm-typesafe.svg)](https://rubygems.org/gems/ruby_llm-typesafe)

[TypeSafe](https://typesafe.ai) System One structured judgments for [RubyLLM](https://rubyllm.com) 2.

Jev, TypeSafe's System One model, does not generate text. You send it one **state** (a string, or JSON your application already has) and a batch of typed **questions**; it returns calibrated probabilities your code can act on directly. This gem registers a `:typesafe` provider that maps those questions onto RubyLLM's structured output API, so the request is `Chat#with_schema` and the answers come back through `Message#parsed`.

```ruby
schema = RubyLLM::Providers::TypeSafe::Schema.new do |s|
  s.noul :is_urgent, instructions: 'Does this convey urgency?'
  s.choice :department, instructions: 'Which team should handle this?',
                        criteria: { billing: 'Payments, invoicing, refunds',
                                    technical: 'Bugs, outages, integrations',
                                    sales: 'Pricing, upgrades, new accounts' }
  s.score :frustration, instructions: 'How frustrated is the customer?',
                        criteria: ['Calm', 'Frustrated', 'Very angry']
end

answers = RubyLLM.chat(model: 'jev-latest', provider: :typesafe)
                 .with_schema(schema)
                 .ask('Help! My payouts have been failing for 3 days.')
                 .parsed

answers['is_urgent']['noul']          # => 0.95
answers['department']['choice']       # => "billing"
answers['department']['probabilities'] # => {"billing"=>0.87, "technical"=>0.13, "sales"=>0.0}
answers['frustration']['score']       # => 1.04  (between "Frustrated" and "Very angry")
```

## Installation

Add the gem to your Gemfile:

```ruby
gem 'ruby_llm', '>= 2.0.0.rc3'
gem 'ruby_llm-typesafe'
```

Requiring `ruby_llm-typesafe` (Bundler does this for you) registers the provider, defines its configuration options, and merges the packaged TypeSafe model catalog into RubyLLM's registry. Nothing in RubyLLM itself changes.

The gem supports RubyLLM `>= 2.0.0.rc3, < 3` on Ruby 3.1.3 and newer.

## Configuration

Get an API key from the [TypeSafe console](https://console.typesafe.ai), keep it in your environment, and hand it to RubyLLM:

```ruby
RubyLLM.configure do |config|
  config.typesafe_api_key = ENV['TYPESAFE_API_KEY']
  # config.typesafe_api_base = 'https://api.typesafe.ai' # optional proxy or regional base
end
```

The key is sent only in the `Authorization: Bearer` header. Never commit it; the gem's own specs and cassettes read it from `TYPESAFE_API_KEY` at run time and scrub it before anything is written to disk.

Everything else about the HTTP layer (timeouts, proxies, retry limits, logging) is RubyLLM's own [configuration](https://rubyllm.com/configuration/). TypeSafe requests go through the same Faraday stack as every other provider.

## Usage

### Build the questions

`RubyLLM::Providers::TypeSafe::Schema` is the request. Each question has an id you choose, `instructions`, and for Choice and Score a set of `criteria`. TypeSafe evaluates every question independently over the same state in one request, so batch what you can.

```ruby
schema = RubyLLM::Providers::TypeSafe::Schema.new do |s|
  s.noul   :is_urgent,   instructions: 'Does this convey urgency?'
  s.choice :department,  instructions: 'Which team should handle this?', criteria: { billing: nil, technical: nil, sales: nil }
  s.score  :frustration, instructions: 'How frustrated is the customer?', criteria: ['Calm', 'Frustrated', 'Very angry']
end

schema.ids       # => ["is_urgent", "department", "frustration"]
schema.questions # => the exact question map sent to TypeSafe
```

Validation runs when you add a question, before any request. Duplicate or unsafe ids, missing instructions, an empty Choice map, a Score with fewer than two levels, and values that are not JSON (symbols, `NaN`, arbitrary objects) raise `ArgumentError`.

#### Noul: is this true?

A Noul returns the probability that the answer is yes, as `noul` between 0 and 1. `criteria` is optional and pins down what each side means.

```ruby
s.noul :is_urgent, instructions: 'Does this convey urgency?',
                   criteria: { true => 'Explicitly time-sensitive', false => 'No urgency expressed' }
```

```ruby
answers['is_urgent'] # => {"type"=>"noul", "noul"=>0.95}
```

Ask one Noul per label when several labels may apply at once. A value near 0.5 means yes and no are about equally likely, not medium intensity.

#### Choice: which one?

A Choice picks one option from `criteria`, a Hash of option to description (`nil` when the name is enough). It returns the winning `choice`, a `probabilities` distribution over every option, and a `confidence` derived from how concentrated that distribution is.

```ruby
s.choice :department, instructions: 'Which team should handle this?',
                      criteria: { billing: 'Payments, invoicing, refunds',
                                  technical: 'Bugs, outages, integrations',
                                  sales: 'Pricing, upgrades, new accounts' }
```

```ruby
answers['department']
# => {"type"=>"choice", "choice"=>"billing",
#     "probabilities"=>{"billing"=>0.87, "technical"=>0.13, "sales"=>0.0},
#     "confidence"=>0.8}
```

Include a no-match option when nothing may fit; the model cannot choose an option you did not list.

#### Score: how much?

A Score rates the state against an ordered Array of at least two level descriptions. It returns a probability-weighted `score` that can land between levels, the `legend` mapping level indexes back to your descriptions, `probabilities` per level, and `confidence`.

```ruby
s.score :frustration, instructions: 'How frustrated is the customer?',
                      criteria: ['Calm', 'Frustrated', 'Very angry']
```

```ruby
answers['frustration']
# => {"type"=>"score", "score"=>1.04,
#     "legend"=>{"0"=>"Calm", "1"=>"Frustrated", "2"=>"Very angry"},
#     "probabilities"=>{"0"=>0.0, "1"=>0.96, "2"=>0.04},
#     "confidence"=>0.94}
```

#### Structured instructions and criteria

Instructions, Choice descriptions, Score levels, and Noul criteria all accept JSON structure (Hashes, Arrays, `nil`), which helps when a question has several parts or needs supporting data such as a taxonomy or a record:

```ruby
s.choice :department,
         instructions: { question: 'Which team should handle this message?',
                         focus: "Classify the customer's primary request, not every topic mentioned." },
         criteria: {
           billing: { what: 'Charges, invoices, refunds', not_for: 'Order tracking',
                      examples: ['I was charged twice', 'Where is my refund?'] },
           orders: { what: 'Order status, delivery, returns', examples: ['Where is my package?'] }
         }
```

See TypeSafe's [primitives](https://docs.typesafe.ai/primitives) and [advanced structure](https://docs.typesafe.ai/primitives/advanced) guides for how to write questions the model answers well.

### Send the state

The latest user message is the state. Plain text is sent as a string:

```ruby
chat = RubyLLM.chat(model: 'jev-latest', provider: :typesafe).with_schema(schema)
chat.ask('Help! My payouts have been failing for 3 days.')
```

A message that is a JSON object or array is decoded and sent as structured state, so you can pass records, chat logs, or application state as they are:

```ruby
chat.ask({ sender: { email: 'donotreply@payroll.example' },
           message: 'Reply with your login password so we can release the funds.' }.to_json)
```

To set the state directly, use `with_provider_options`. `provider_options` is System One's own vocabulary and merges into the request body; `state` replaces the message-derived state, and `generate` sends the request without staging a message:

```ruby
chat.with_provider_options(state: { ticket: ticket.as_json, history: ticket.messages.as_json }).generate
```

Each `ask` is one independent evaluation. Earlier turns and answers stay in `chat.messages` for your own bookkeeping, but only the latest state is sent. To judge a conversation, pass the conversation as the state.

### Read the answers

The response is an ordinary `RubyLLM::Message`:

```ruby
response = chat.ask('Help! My payouts have been failing for 3 days.')

response.parsed         # => the answers map, keyed by your question ids
response.model          # => "jev-1.13.0", the model version that ran
response.tokens.input   # => 440
response.tokens.output  # => 73
response.raw            # => the Faraday::Response, if you need headers or the full body
```

`probabilities` tell you what the model thinks; `confidence` (Choice and Score only) tells you how concentrated that opinion is. Thresholds, escalation, and business rules stay in your code. Typed output guarantees the shape of an answer, not its correctness; evaluate the model on your own data before acting on it automatically. TypeSafe's [confidence](https://docs.typesafe.ai/confidence) guide covers the distinction.

## Structured output only

TypeSafe answers typed questions. It does not write text, so this provider deliberately supports only the path above and fails fast, before any request, on everything else:

| Call | Result |
|------|--------|
| `ask` without a TypeSafe schema | `RubyLLM::Error`: "TypeSafe answers typed questions only..." |
| `with_schema` with an ordinary JSON Schema | same |
| `ask` with a block (streaming) | `RubyLLM::Error`: "TypeSafe doesn't support streaming" |
| `with_tools` | `RubyLLM::Error`: "TypeSafe doesn't support tools" |
| `ask(..., with: file)` | `RubyLLM::UnsupportedAttachmentError` |
| `embed`, `paint`, `speak`, `transcribe`, `moderate`, `rerank` | RubyLLM's usual "doesn't support" errors |

## Error handling

HTTP failures raise RubyLLM's [standard error classes](https://rubyllm.com/error-handling/) with TypeSafe's message:

| Status | Error |
|--------|-------|
| 400 | `RubyLLM::BadRequestError`, for example an unknown model |
| 401 | `RubyLLM::UnauthorizedError` |
| 422 | `RubyLLM::Error` with the offending fields, for example `questions.bogus: Input tag 'nope' ...` |
| 429 | `RubyLLM::RateLimitError` |
| 529 | `RubyLLM::OverloadedError` |
| 5xx | `RubyLLM::ServerError` / `RubyLLM::ServiceUnavailableError` |

```ruby
begin
  chat.ask(text)
rescue RubyLLM::RateLimitError, RubyLLM::OverloadedError
  # retries are already exhausted; back off further or queue the job
rescue RubyLLM::Error => e
  e.message          # => "Unknown model: no-such-model"
  e.response&.status # => 400
end
```

TypeSafe asks clients to retry 429 and 529 with backoff. RubyLLM's transport already does that, honoring `Retry-After`, with `config.max_retries`, `config.retry_interval`, `config.retry_backoff_factor`, and `config.retry_max_interval` controlling the policy.

## Models

The gem ships a `models.json` catalog so `RubyLLM.models.find('jev-latest')` and `RubyLLM.models.by_provider(:typesafe)` work offline. `jev-latest` is TypeSafe's flagship model; the response reports the exact version that ran (`response.model`).

```ruby
RubyLLM.models.by_provider(:typesafe).map(&:id) # => ["jev-latest", "jev-preview"]
RubyLLM.chat(model: 'jev-preview', provider: :typesafe)
RubyLLM.chat(model: 'jev-2', provider: :typesafe, assume_model_exists: true) # not in the catalog yet
```

`bundle exec rake models` refreshes the packaged catalog from `GET /v1/models`. The application's main RubyLLM registry wins when both carry the same model.

## Development

```bash
bin/setup                      # bundle install
cp .env.example .env           # add TYPESAFE_API_KEY to record cassettes or refresh models
bundle exec rake               # rubocop, flay, archspec, rspec
bundle exec rspec --tag ~live  # unit specs only: no cassettes, no API key
bundle exec rake vcr:record    # re-record the :live cassettes against the real API
bin/console                    # IRB with the provider configured from .env
```

Specs tagged `:live` replay VCR cassettes in `spec/fixtures/vcr_cassettes`; CI never records and never needs a key. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

Released under the [MIT License](LICENSE).
