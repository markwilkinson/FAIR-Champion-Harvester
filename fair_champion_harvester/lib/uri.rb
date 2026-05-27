# frozen_string_literal: true

# This file is named uri.rb, which means 'require "uri"' resolves here instead
# of the stdlib when lib/ is on the load path. We load the real stdlib first.
require File.join(RbConfig::CONFIG["rubylibdir"], "uri")

module FAIRChampionHarvester
  class Uri
    def self.resolve_uri(guid, meta)
      type, url = Core.convertToURL(guid)
      meta.guidtype = type if meta.guidtype.nil?

      meta.comments << "INFO: Found a URI.\n"
      meta.comments << "INFO:  Attempting to resolve #{url} using HTTP Headers #{FAIRChampionHarvester::Utils::AcceptHeader}.\n"
      FAIRChampionHarvester::URL.resolve_url(guid: url, meta: meta, nolinkheaders: false)
      meta.comments << "INFO:  Attempting to resolve #{url} using HTTP Headers #{FAIRChampionHarvester::Utils::XML_FORMATS["xml"].join(",")}.\n"
      FAIRChampionHarvester::URL.resolve_url(guid: url, meta: meta, nolinkheaders: false,
                                             headers: { "Accept" => "#{FAIRChampionHarvester::Utils::XML_FORMATS["xml"].join(",")}" })
      meta.comments << "INFO:  Attempting to resolve #{url} using HTTP Headers #{FAIRChampionHarvester::Utils::JSON_FORMATS["json"].join(",")}.\n"
      FAIRChampionHarvester::URL.resolve_url(guid: url, meta: meta, nolinkheaders: false,
                                             headers: { "Accept" => "#{FAIRChampionHarvester::Utils::JSON_FORMATS["json"].join(",")}" })
      meta.comments << "INFO:  Attempting to resolve #{url} using HTTP Headers 'Accept: */*'.\n"
      FAIRChampionHarvester::URL.resolve_url(guid: url, meta: meta, nolinkheaders: false,
                                             headers: { "Accept" => "*/*" })
      meta
    end
  end
end
