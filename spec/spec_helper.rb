# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
  minimum_coverage line: 99, branch: 85
end

require "psn_client"
require "webmock/rspec"
require "json"

module FixtureHelper
  def fixture(name)
    JSON.parse(File.read(File.expand_path("fixtures/#{name}.json", __dir__)))
  end
end

RSpec.configure do |config|
  config.include FixtureHelper
  config.disable_monkey_patching!
  config.order = :random
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
