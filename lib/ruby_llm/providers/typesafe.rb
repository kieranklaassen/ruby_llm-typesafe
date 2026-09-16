# frozen_string_literal: true

require 'ruby_llm'
require 'json'

require_relative '../protocols/system_one'
require_relative 'typesafe/schema'

module RubyLLM
  module Providers
    # TypeSafe API integration. Jev, TypeSafe's System One model, evaluates
    # one state against typed Choice, Noul, and Score questions and returns
    # calibrated probabilities instead of generated text, so this provider
    # serves structured output only: build the questions with Schema, pass
    # them to Chat#with_schema, and read the answers from Message#parsed.
    #
    #   RubyLLM.configure { |config| config.typesafe_api_key = ENV['TYPESAFE_API_KEY'] }
    #
    #   schema = RubyLLM::Providers::TypeSafe::Schema.new do |s|
    #     s.noul :is_urgent, instructions: 'Does this convey urgency?'
    #   end
    #
    #   RubyLLM.chat(model: 'jev-latest', provider: :typesafe)
    #          .with_schema(schema)
    #          .ask('Help! My payouts have been failing for 3 days.')
    #          .parsed # => {"is_urgent" => {"type" => "noul", "noul" => 0.95}}
    class TypeSafe < Provider
      # The version of the ruby_llm-typesafe gem, as a string.
      VERSION = '0.1.0'

      protocol :system_one, Protocols::SystemOne

      def api_base
        @config.typesafe_api_base || 'https://api.typesafe.ai'
      end

      def headers
        { 'Authorization' => "Bearer #{@config.typesafe_api_key}" }
      end

      # TypeSafe reports failures under +detail+: a Hash with a +message+ for
      # API usage errors, or a list of offending fields for 422 validation
      # failures. Neither shape is one the generic parser reads.
      def parse_error(response)
        body = parse_error_body(response)
        detail = body['detail'] if body.is_a?(Hash)

        case detail
        when Hash then detail['message'] || super
        when Array then detail.map { |part| validation_message(part) }.join('; ')
        else super
        end
      end

      class << self
        def configuration_options
          %i[typesafe_api_key typesafe_api_base]
        end

        def configuration_requirements
          %i[typesafe_api_key]
        end
      end

      private

      def validation_message(part)
        return part.to_s unless part.is_a?(Hash)

        location = Array(part['loc']).reject { |segment| segment == 'body' }.join('.')
        message = part['msg'] || JSON.generate(part)
        location.empty? ? message : "#{location}: #{message}"
      end
    end
  end
end

RubyLLM::Provider.register :typesafe, RubyLLM::Providers::TypeSafe,
                           models: File.expand_path('../../../models.json', __dir__)
