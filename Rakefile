# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task default: %i[spec rubocop rbs steep]

desc "Validate RBS signatures"
task :rbs do
  sh "bundle exec rbs -I sig -r delegate validate"
end

desc "Type-check lib against sig with Steep"
task :steep do
  sh "bundle exec steep check"
end
