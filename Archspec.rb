# frozen_string_literal: true

source 'lib/**/*.rb'

component :provider,
          in: %w[
            lib/ruby_llm/providers/typesafe.rb
            lib/ruby_llm/providers/typesafe/**/*.rb
          ],
          namespace: 'RubyLLM::Providers::TypeSafe'

component :protocol,
          in: %w[
            lib/ruby_llm/protocols/system_one.rb
            lib/ruby_llm/protocols/system_one/**/*.rb
          ],
          namespace: 'RubyLLM::Protocols::SystemOne'

# The wire format never names the provider that speaks it; the provider
# declares the protocol and builds the questions it carries.
protocol.cannot_reference_constants 'RubyLLM::Providers', 'RubyLLM::Providers::TypeSafe'
provider.cannot_reference_constants 'RSpec', 'WebMock', 'VCR'
protocol.cannot_reference_constants 'RSpec', 'WebMock', 'VCR'

preset :ruby_conventions
