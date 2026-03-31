# frozen_string_literal: true

require_relative "lib/fair_champion_harvester/version"

Gem::Specification.new do |spec|
  spec.name          = "fair_champion_harvester"
  spec.version       = FairChampionHarvester::VERSION
  spec.authors       = ["markwilkinson"]
  spec.email         = ["mark.wilkinson@upm.es"]
  spec.summary       = "This is the metadata harvesting engine used by the FAIR Champion."
  spec.description   = "Follow all kinds of paths to look for metadata based on whatever GUID is provided."
  spec.homepage      = "https://github.com/markwilkinson/FAIR-Champion-Harvester"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = "https://github.com/markwilkinson/FAIR-Champion-Harvester"
  spec.metadata["changelog_uri"]     = "https://github.com/markwilkinson/FAIR-Champion-Harvester/CHANGELOG.md"

  # Files to include in the gem
  gemspec_file = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      f == gemspec_file ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml])
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # ====================== RUNTIME DEPENDENCIES ======================
  # These are required when someone installs and uses your gem.
  # Only put gems here that your library actually needs at runtime.

  spec.add_runtime_dependency "base64", "~> 0.3"
  spec.add_runtime_dependency "bcrypt" # if your code actually uses BCrypt directly
  spec.add_runtime_dependency "connection_pool", "~> 2.4", "< 3.0"
  spec.add_runtime_dependency "ftr_ruby", "~> 0.1.6"
  spec.add_runtime_dependency "http", "~> 6.0"
  spec.add_runtime_dependency "json", "~> 2.7"
  spec.add_runtime_dependency "json-canonicalization", "~> 1.0"
  spec.add_runtime_dependency "jsonpath", "~> 1.1"
  spec.add_runtime_dependency "linkeddata", "~> 3.1"
  spec.add_runtime_dependency "multi_json", "1.15.0"
  spec.add_runtime_dependency "nokogiri", "1.18.10"
  spec.add_runtime_dependency "openapi3_parser", "~> 0.9"
  spec.add_runtime_dependency "parseconfig", "~> 1.1"
  spec.add_runtime_dependency "puma", "~> 6.4"
  spec.add_runtime_dependency "rdf-raptor", "~> 3.2"
  spec.add_runtime_dependency "rdf-vocab"
  spec.add_runtime_dependency "require_all", "~> 3.0"
  spec.add_runtime_dependency "rest-client", "~> 2.1"
  spec.add_runtime_dependency "sinatra", "~> 2.2"
  spec.add_runtime_dependency "sinatra-cross_origin"
  spec.add_runtime_dependency "swagger-blocks", "~> 3.0"
  spec.add_runtime_dependency "triple_easy", "~> 0.1.0"
  spec.add_runtime_dependency "xml-simple", "~> 1.1"

  # ====================== DEVELOPMENT DEPENDENCIES ======================
  # These are only installed when developing the gem itself (not when users install it)

  spec.add_development_dependency "dotenv", "~> 2.8"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop"
end
