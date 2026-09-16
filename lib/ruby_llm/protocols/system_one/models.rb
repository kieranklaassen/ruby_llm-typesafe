# frozen_string_literal: true

module RubyLLM
  module Protocols
    class SystemOne < Protocol
      # Lists the models available to the account from GET v1/models. The
      # endpoint returns a name, description, and release date per model;
      # every System One model takes text state and returns structured
      # answers, which is all the catalog can say about them.
      module Models
        MODALITIES = { input: %w[text], output: %w[text] }.freeze
        CAPABILITIES = %w[structured_output].freeze

        module_function

        def models_url
          'v1/models'
        end

        def parse_list_models_response(response, slug)
          cards = response.body['models'] if response.body.is_a?(Hash)
          unless cards.is_a?(Array)
            raise Error.new('TypeSafe returned an unexpected models list; expected { models: [...] }',
                            response: response)
          end

          cards.map { |card| model_from(card, slug) }
        end

        def model_from(card, slug)
          Model.new(
            id: card['name'],
            name: card['name'],
            provider: slug,
            family: card['name'].to_s.split('-').first,
            created_at: card['release_date'],
            modalities: MODALITIES,
            capabilities: CAPABILITIES,
            metadata: { description: card['description'] }
          )
        end
      end
    end
  end
end
