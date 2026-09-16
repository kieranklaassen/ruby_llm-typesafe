# frozen_string_literal: true

require 'json'

module RubyLLM
  module Protocols
    class SystemOne < Protocol
      # Renders POST v1/systemone requests and parses their answers. See
      # https://docs.typesafe.ai/api for the wire contract.
      module Chat
        # The schema extension key that carries the question map.
        QUESTIONS_KEY = 'x-typesafe'

        module_function

        def completion_url
          'v1/systemone'
        end

        def render_payload(messages, model:, schema:, state: nil, **)
          {
            model: model.id,
            state: state.nil? ? state_from(messages) : state,
            questions: questions_from(schema)
          }
        end

        def parse_completion_body(body, raw: nil)
          unless documented_body?(body)
            raise Error.new('TypeSafe returned an unexpected response body; expected model, answers, and usage',
                            response: raw)
          end

          answers, usage = body.values_at('answers', 'usage')
          Message.new(
            role: :assistant,
            content: JSON.generate(answers),
            model: body['model'],
            input_tokens: usage['input_tokens'],
            output_tokens: usage['output_tokens'],
            finish_reason: :stop,
            raw: raw
          )
        end

        # Reads the question map out of a schema normalized by
        # Chat#with_schema, or +nil+ when the schema carries none.
        def questions_in(schema)
          return unless schema.is_a?(Hash)

          definition = fetch(schema, 'schema') || schema
          extension = fetch(definition, QUESTIONS_KEY)
          questions = fetch(extension, 'questions')
          return unless questions.is_a?(Hash) && !questions.empty?

          JSON.parse(JSON.generate(questions))
        end

        def questions_from(schema)
          questions_in(schema) || raise(
            Error,
            'TypeSafe answers typed questions only. Build them with RubyLLM::Providers::TypeSafe::Schema ' \
            'and pass the schema to with_schema.'
          )
        end

        # Each ask is one independent evaluation, so only the latest user
        # turn becomes state. Earlier turns and answers stay in the transcript.
        def state_from(messages)
          message = messages.reverse.find { |candidate| candidate.role == :user }
          if message.nil? || message.content.nil?
            raise Error, 'TypeSafe needs state to evaluate. Ask with text, or set state through with_provider_options.'
          end
          raise UnsupportedAttachmentError, message.attachments.first.mime_type unless message.attachments.empty?

          structured_state(message.content)
        end

        # User content that parses to a JSON object or array is sent as
        # structured state. JSON scalars and everything else stay the string
        # the caller wrote, since state is string, object, or array.
        def structured_state(content)
          return content unless content.is_a?(String) && content.lstrip.start_with?('{', '[')

          parsed = JSON.parse(content)
          parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : content
        rescue JSON::ParserError
          content
        end

        def documented_body?(body)
          body.is_a?(Hash) && body['model'].is_a?(String) && body['answers'].is_a?(Hash) && body['usage'].is_a?(Hash)
        end

        def fetch(hash, key)
          return unless hash.is_a?(Hash)

          hash.key?(key) ? hash[key] : hash[key.to_sym]
        end
      end
    end
  end
end
