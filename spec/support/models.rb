# frozen_string_literal: true

# The provider and model matrix the live specs iterate over. TypeSafe serves
# structured output only, so there is one matrix and no chat, tool,
# embedding, or media rows.
PROVIDER = :typesafe
STRUCTURED_OUTPUT_MODELS = [
  { provider: :typesafe, model: 'jev-latest' }
].freeze

def each_model(models)
  models.each { |model_info| yield model_info[:provider], model_info[:model], model_info }
end

# Selects the model the live specs use for +provider+. Keep literal ids only
# when the exact name is the behavior under test.
def model_for(provider = PROVIDER)
  STRUCTURED_OUTPUT_MODELS.find { |model_info| model_info[:provider] == provider }.fetch(:model)
end
