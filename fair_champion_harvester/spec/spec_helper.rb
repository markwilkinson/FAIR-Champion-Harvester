# frozen_string_literal: true

require "fair_champion_harvester"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run :live examples by default; skip them with: rspec --tag ~live
  # Run only live examples with: rspec --tag live
end
