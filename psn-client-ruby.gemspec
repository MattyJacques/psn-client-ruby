# frozen_string_literal: true

require_relative "lib/psn_client/version"

Gem::Specification.new do |spec|
  spec.name = "psn-client-ruby"
  spec.version = PSN::VERSION
  spec.authors = ["Matthew"]
  spec.email = ["iftw@live.co.uk"]
  spec.summary = "Unofficial PlayStation Network API client"
  spec.description = "Retrieve games played, trophies earned, transaction history and " \
                     "entitlements for a PlayStation Network account."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "faraday-retry", "~> 2.2"
end
