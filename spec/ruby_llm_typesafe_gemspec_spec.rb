# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ruby_llm-typesafe gemspec' do # rubocop:disable RSpec/DescribeClass
  let(:gemspec) { Gem::Specification.load(File.expand_path('../ruby_llm-typesafe.gemspec', __dir__)) }
  let(:ruby_llm_requirement) { gemspec.dependencies.find { |dependency| dependency.name == 'ruby_llm' }.requirement }

  it 'matches the VERSION constant' do
    expect(gemspec.version.to_s).to eq(RubyLLM::Providers::TypeSafe::VERSION)
    expect(RubyLLM::Providers::TypeSafe::VERSION).to eq('0.1.0')
  end

  it 'depends on RubyLLM 2 only' do
    expect(ruby_llm_requirement.satisfied_by?(Gem::Version.new('2.0.0.rc3'))).to be(true)
    expect(ruby_llm_requirement.satisfied_by?(Gem::Version.new('2.4.1'))).to be(true)
    expect(ruby_llm_requirement.satisfied_by?(Gem::Version.new('1.16.0'))).to be(false)
    expect(ruby_llm_requirement.satisfied_by?(Gem::Version.new('3.0.0'))).to be(false)
  end

  it 'supports the RubyLLM 2 Ruby baseline under the MIT license' do
    expect(gemspec.license).to eq('MIT')
    expect(gemspec.required_ruby_version.satisfied_by?(Gem::Version.new('3.1.3'))).to be(true)
    expect(gemspec.required_ruby_version.satisfied_by?(Gem::Version.new('3.0.0'))).to be(false)
    expect(gemspec.metadata['rubygems_mfa_required']).to eq('true')
  end

  it 'packages the runtime files, catalog, changelog, README, and license' do
    expect(gemspec.files).to include(
      'lib/ruby_llm-typesafe.rb',
      'lib/ruby_llm/providers/typesafe.rb',
      'lib/ruby_llm/providers/typesafe/schema.rb',
      'lib/ruby_llm/providers/typesafe/schema/answers.rb',
      'lib/ruby_llm/protocols/system_one.rb',
      'lib/ruby_llm/protocols/system_one/chat.rb',
      'lib/ruby_llm/protocols/system_one/models.rb',
      'models.json', 'CHANGELOG.md', 'LICENSE', 'README.md'
    )
    expect(gemspec.files).not_to include(a_string_starting_with('spec/'))
  end

  it 'loads from the hyphenated entrypoint in a clean process' do
    script = "require 'ruby_llm-typesafe'; " \
             "puts RubyLLM::Provider.resolve(:typesafe).name, RubyLLM.models.find('jev-latest', provider: :typesafe).id"
    output = IO.popen([RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script], &:read)

    expect($CHILD_STATUS).to be_success
    expect(output.lines.map(&:strip)).to eq(%w[RubyLLM::Providers::TypeSafe jev-latest])
  end
end
