# frozen_string_literal: true

# === CRITICAL FIX for URI constant issues on Ruby 3.2+ ===
require "uri"
# Force the top-level URI constant to be available globally
::URI # This triggers the autoload properly
# Make sure it's set on Object in case of weird lookup issues
Object.const_set(:URI, ::URI) unless Object.const_defined?(:URI)

# Now safely load the http gem
require "http"
require "json"
require "rdf"
require "rdf/json"
require "rdf/rdfa"
require "json/ld"
require "json/ld/preloaded"
require "rdf/trig"
require "rdf/raptor"
require "rdf/vocab"
require "net/http"
require "net/https" # for openssl
require "rdf/turtle"
require "sparql"
require "tempfile"
require "xmlsimple"
require "nokogiri"
require "parseconfig"
# require "rest-client"
require "cgi"
require "digest"
require "open3"
require "rdf/xsd"
require "require_all"
# require 'pry'
require_relative "fair_champion_harvester/version"
require_relative "./utils"
require_relative "./config"
# Loads everything inside the ./ directory (relative to current file)
require_rel "../lib"

module FAIRChampionHarvester
  class Error < StandardError; end
  # Your code goes here...
end
