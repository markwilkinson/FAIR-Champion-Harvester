# frozen_string_literal: true

# === CRITICAL FIX for URI constant issues on Ruby 3.2+ ===
require "uri"

require "http"
require "json"
require "linkeddata"
require "json/ld"
require "json/ld/preloaded"
require "rdf/raptor"
require "rdf/vocab"
require "net/http"
require "net/https" # for openssl
require "sparql"
require "tempfile"
require "xmlsimple"
require "nokogiri"
require "parseconfig"
# require "rest-client"
require "cgi"
require "digest"
require "open3"
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
