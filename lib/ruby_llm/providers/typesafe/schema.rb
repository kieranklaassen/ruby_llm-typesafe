# frozen_string_literal: true

require 'json'
require_relative 'schema/answers'

module RubyLLM
  module Providers
    class TypeSafe < Provider
      # Builds the batch of typed System One questions a chat sends to
      # TypeSafe. Pass an instance to Chat#with_schema: RubyLLM sees a JSON
      # Schema that describes the typed answer map, and the protocol reads
      # the question payload back out of the schema's +x-typesafe+ key.
      #
      #   schema = RubyLLM::Providers::TypeSafe::Schema.new do |s|
      #     s.noul :is_urgent, instructions: 'Does this convey urgency?'
      #     s.choice :department, instructions: 'Which team should handle this?',
      #                           criteria: { billing: 'Payments and refunds', technical: 'Bugs and outages' }
      #     s.score :frustration, instructions: 'How frustrated is the customer?',
      #                           criteria: ['Calm', 'Frustrated', 'Very angry']
      #   end
      #
      # Every question needs a unique id, +instructions+, and, for Choice and
      # Score, +criteria+. Instructions and criteria accept strings or JSON
      # structure (Hash, Array, nil), as documented at
      # https://docs.typesafe.ai/primitives/advanced. Validation happens
      # here, before any request; invalid input raises ArgumentError.
      class Schema
        NAME = 'typesafe_answers'
        ID_PATTERN = /\A[A-Za-z0-9_.-]+\z/
        NOUL_CRITERIA_KEYS = %w[true false].freeze

        # Returns the question payloads keyed by id, exactly as sent to TypeSafe.
        attr_reader :questions

        # Creates a schema and yields it to +block+ for adding questions.
        def initialize
          @questions = {}
          yield self if block_given?
        end

        # Adds a yes/no question. Returns the probability the answer is yes.
        # +criteria+ may describe what +true+ and +false+ mean. Returns +self+.
        #
        #   s.noul :is_urgent, instructions: 'Does this convey urgency?',
        #                      criteria: { true: 'Explicitly time-sensitive', false: 'No urgency expressed' }
        #
        def noul(id, instructions:, criteria: nil)
          add(id, 'noul', instructions, noul_criteria(id, criteria))
        end

        # Adds a question that picks one option from +criteria+, a Hash of
        # option to description (+nil+ when the option needs no detail).
        # Returns +self+.
        #
        #   s.choice :department, instructions: 'Which team should handle this?',
        #                         criteria: { billing: 'Payments, invoicing, refunds', sales: nil }
        #
        def choice(id, instructions:, criteria:)
          unless criteria.is_a?(Hash) && !criteria.empty?
            raise ArgumentError, "#{id}: choice criteria must be a non-empty Hash of options"
          end

          options = criteria.to_h do |option, description|
            [validate_key(id, option, 'choice option'), validate_description(id, description, 'choice option')]
          end
          add(id, 'choice', instructions, options)
        end

        # Adds a question that rates the state along +criteria+, an ordered
        # Array of at least two level descriptions. Returns +self+.
        #
        #   s.score :frustration, instructions: 'How frustrated is the customer?',
        #                         criteria: ['Calm', 'Frustrated', 'Very angry']
        #
        def score(id, instructions:, criteria:)
          unless criteria.is_a?(Array) && criteria.size >= 2
            raise ArgumentError, "#{id}: score criteria must be an Array of at least two ordered levels"
          end

          levels = criteria.map { |level| validate_description(id, level, 'score level') }
          add(id, 'score', instructions, levels)
        end

        # Returns the question ids in insertion order.
        def ids
          @questions.keys
        end

        # Returns whether no questions have been added.
        def empty?
          @questions.empty?
        end

        # Returns the number of questions.
        def size
          @questions.size
        end

        # Returns the structured-output schema RubyLLM hands to the provider:
        # a JSON Schema for the typed answer map with the question payload
        # under the +x-typesafe+ key.
        def to_json_schema
          raise ArgumentError, 'TypeSafe schema has no questions; add at least one noul, choice, or score' if empty?

          {
            'name' => NAME,
            'description' => 'TypeSafe System One answers keyed by question id',
            'schema' => {
              'type' => 'object',
              'properties' => @questions.transform_values { |question| Answers.for(question) },
              'required' => ids,
              Protocols::SystemOne::Chat::QUESTIONS_KEY => { 'questions' => deep_copy(@questions) }
            }
          }
        end

        alias to_h to_json_schema

        def to_json(*args)
          to_json_schema.to_json(*args)
        end

        private

        def add(id, type, instructions, criteria)
          key = validate_id(id)
          question = { 'type' => type, 'instructions' => validate_instructions(key, instructions) }
          question['criteria'] = criteria unless criteria.nil?
          @questions[key] = deep_copy(question)
          self
        end

        def validate_id(id)
          key = id.to_s if id.is_a?(Symbol) || id.is_a?(String)
          unless key&.match?(ID_PATTERN)
            raise ArgumentError,
                  "question id #{id.inspect} must be a String or Symbol of letters, digits, '_', '.', or '-'"
          end
          raise ArgumentError, "question id #{key.inspect} is already defined" if @questions.key?(key)

          key
        end

        def validate_instructions(id, instructions)
          raise ArgumentError, "#{id}: instructions are required" if instructions.nil? || instructions == ''

          validate_json(id, instructions, 'instructions')
        end

        def noul_criteria(id, criteria)
          return if criteria.nil?
          unless criteria.is_a?(Hash)
            raise ArgumentError, "#{id}: noul criteria must be a Hash with only true and false keys"
          end

          criteria.to_h do |key, description|
            normalized = key.to_s
            unless NOUL_CRITERIA_KEYS.include?(normalized)
              raise ArgumentError, "#{id}: noul criteria key #{key.inspect} must be true or false"
            end

            [normalized, validate_description(id, description, 'noul criteria')]
          end
        end

        def validate_key(id, key, label)
          unless (key.is_a?(String) || key.is_a?(Symbol)) && !key.to_s.empty?
            raise ArgumentError, "#{id}: #{label} keys must be non-empty Strings or Symbols"
          end

          key.to_s
        end

        def validate_description(id, value, label)
          return if value.nil?

          validate_json(id, value, label)
        end

        def validate_json(id, value, label)
          case value
          when String, Integer, true, false, nil
            value
          when Float
            raise ArgumentError, "#{id}: #{label} contains a non-finite number" unless value.finite?

            value
          when Array
            value.each { |item| validate_json(id, item, label) }
          when Hash
            value.each do |key, item|
              validate_key(id, key, label)
              validate_json(id, item, label)
            end
          else
            raise ArgumentError, "#{id}: #{label} contains #{value.class}, which is not JSON-compatible"
          end
        end

        # A JSON round trip yields plain string-keyed data that shares
        # nothing with the caller's objects.
        def deep_copy(value)
          JSON.parse(JSON.generate(value))
        end
      end
    end
  end
end
