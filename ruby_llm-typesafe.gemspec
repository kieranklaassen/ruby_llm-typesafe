# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-typesafe'
  spec.version = '0.1.0'
  spec.authors = ['Kieran Klaassen']
  spec.email = ['kieranklaassen@gmail.com']

  spec.summary = 'RubyLLM provider for TypeSafe System One structured judgments.'
  spec.description = 'Adds a :typesafe provider to RubyLLM 2 that evaluates text or structured state against ' \
                     "TypeSafe's typed Choice, Noul, and Score questions through Chat#with_schema. " \
                     'Structured output only: answers are calibrated probabilities, not generated text.'
  spec.homepage = 'https://github.com/kieranklaassen/ruby_llm-typesafe'
  spec.license = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.1.3')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['documentation_uri'] = "#{spec.homepage}#readme"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('lib/**/*.rb') + %w[models.json CHANGELOG.md LICENSE README.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '>= 2.0.0.rc3', '< 3'
end
