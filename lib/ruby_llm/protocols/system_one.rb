# frozen_string_literal: true

require_relative 'system_one/chat'
require_relative 'system_one/models'

module RubyLLM
  module Protocols
    # TypeSafe's System One API: one state and a map of typed questions in
    # on v1/systemone, a map of typed answers plus usage out, and the model
    # catalog on v1/models. System One generates no text, so streaming,
    # tools, and every non-chat operation stay unimplemented and fail with
    # RubyLLM's usual "doesn't support" errors.
    #
    # The questions travel inside the structured-output schema that
    # Chat#with_schema normalizes, under the +x-typesafe+ extension key;
    # RubyLLM::Providers::TypeSafe::Schema puts them there.
    class SystemOne < Protocol
      include SystemOne::Chat
      include SystemOne::Models

      def complete(messages, tools:, **options, &block)
        raise Error, "#{@provider.name} doesn't support streaming" if block
        raise Error, "#{@provider.name} doesn't support tools" if tools && !tools.empty?

        super(messages, tools: tools, **options)
      end

      # +provider_options+ is System One's own vocabulary and merges into the
      # wire payload, with one exception: an explicit +state+ replaces the
      # state derived from the latest user message instead of deep-merging
      # into it.
      def render(messages, schema: nil, provider_options: {}, before_request: [], **)
        options = provider_options.to_h.transform_keys(&:to_sym)
        payload = render_payload(messages, model: model, schema: schema, state: options.delete(:state))
        payload = RubyLLM::Support::Utils.deep_merge(payload, options)
        apply_before_request_hooks(payload, before_request)
      end
    end
  end
end
