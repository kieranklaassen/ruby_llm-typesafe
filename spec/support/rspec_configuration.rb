# frozen_string_literal: true

require 'fileutils'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed

  # Specs tagged :live replay (or record) the real TypeSafe API through a
  # cassette named after the example. A failing example deletes its cassette
  # so the next run records against the live API instead of replaying a
  # recording that may be hiding the bug.
  config.around(:each, :live) do |example|
    cassette_name = example.full_description.downcase.gsub(/[^a-z0-9]+/, '_').delete_prefix('_').delete_suffix('_')
    cassette_path = File.join(VCR.configuration.cassette_library_dir, "#{cassette_name}.yml")

    VCR.use_cassette(cassette_name) { example.run }
    FileUtils.rm_f(cassette_path) if example.exception
  end
end
