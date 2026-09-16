# frozen_string_literal: true

module RubyLLM
  module Providers
    class TypeSafe < Provider
      class Schema
        # JSON Schema for the typed answer each question type returns. The
        # shapes follow https://docs.typesafe.ai/api#answer-types: a Noul
        # carries one probability, a Choice the chosen option plus a
        # distribution and confidence, a Score the weighted position plus
        # the legend, a distribution over levels, and confidence.
        module Answers
          PROBABILITY = { 'type' => 'number', 'minimum' => 0, 'maximum' => 1 }.freeze

          module_function

          def for(question)
            case question['type']
            when 'noul' then noul
            when 'choice' then choice(question['criteria'].keys)
            when 'score' then score(question['criteria'].size)
            end
          end

          def noul
            {
              'type' => 'object',
              'properties' => { 'type' => { 'const' => 'noul' }, 'noul' => PROBABILITY },
              'required' => %w[type noul]
            }
          end

          def choice(options)
            {
              'type' => 'object',
              'properties' => {
                'type' => { 'const' => 'choice' },
                'choice' => { 'type' => 'string', 'enum' => options },
                'probabilities' => probabilities(options),
                'confidence' => PROBABILITY
              },
              'required' => %w[type choice probabilities confidence]
            }
          end

          # Level descriptions may be structured, so the legend values stay
          # unconstrained.
          def score(level_count)
            levels = Array.new(level_count, &:to_s)
            {
              'type' => 'object',
              'properties' => {
                'type' => { 'const' => 'score' },
                'score' => { 'type' => 'number', 'minimum' => 0, 'maximum' => level_count - 1 },
                'legend' => { 'type' => 'object', 'properties' => levels.to_h { |level| [level, {}] },
                              'required' => levels },
                'probabilities' => probabilities(levels),
                'confidence' => PROBABILITY
              },
              'required' => %w[type score legend probabilities confidence]
            }
          end

          def probabilities(keys)
            {
              'type' => 'object',
              'properties' => keys.to_h { |key| [key, PROBABILITY] },
              'required' => keys
            }
          end
        end
      end
    end
  end
end
