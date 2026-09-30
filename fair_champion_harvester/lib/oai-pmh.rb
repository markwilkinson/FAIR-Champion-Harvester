# frozen_string_literal: true

module FAIRChampionHarvester
  # Harvests metadata about a GUID from an OAI-PMH server, when one can be found.
  #
  # The hard part of OAI-PMH is finding the endpoint: nothing in a GUID or its
  # landing page says where it is. Two discovery strategies are tried, in order:
  #
  #  1. FAIRiCat (https://signposting.org/FAIRiCat/) — the publisher declares it.
  #     The catalog is found via a +Link: <...>; rel="api-catalog"+ header, or at
  #     +/.well-known/api-catalog+, and is an application/linkset+json document
  #     in which the OAI-PMH endpoint is the +anchor+ of an entry whose
  #     service-doc / service-meta / service-desc links point at the OAI
  #     protocol specification or at a +?verb=Identify+ URL.
  #
  #  2. Heuristics — we guess from links already seen on the resource (HTTP Link
  #     headers and HTML <link> elements): any href carrying an OAI-PMH +verb=+
  #     query, or whose path ends in a conventional name (+/oai+, +/oai2d+ ...).
  #
  # Every candidate, from either strategy, is verified with an +Identify+ request
  # before it is believed, so a wrong guess costs one request and produces no
  # false positives.
  class OAIPMH
    VERBS = %w[GetRecord Identify ListIdentifiers ListMetadataFormats ListRecords ListSets].freeze
    VERB_QUERY = /(?:\A|[&;])verb=(?:#{VERBS.join("|")})(?:[&;]|\z)/
    PATH_NAME = %r{/(?:oai|oai2d?|oai-pmh|oai_pmh|oaipmh|oai/request|oaiprovider/request)/?\z}i
    SPEC_URL = %r{openarchives\.org/OAI/(?:2\.0/)?openarchivesprotocol}i
    FAIRICAT_TYPE = "application/linkset+json"
    FAIRICAT_PROFILE = "https://signposting.org/FAIRiCat/"
    SERVICE_RELS = %w[service-doc service-meta service-desc].freeze
    # URIs whose origin is a resolver, not a repository; never look for a catalog there
    RESOLVER_HOSTS = %w[doi.org dx.doi.org hdl.handle.net n2t.net purl.org w3id.org].freeze
    XML_ACCEPT = { "Accept" => "text/xml, application/xml;q=0.9, */*;q=0.1" }.freeze
    DC_NS = "http://purl.org/dc/elements/1.1/"
    # richer formats worth fetching in addition to the mandatory oai_dc, best first
    PREFERRED_PREFIXES = %w[oai_datacite datacite4 datacite oai_rdf rdf].freeze
    MAX_IDENTIFIER_ATTEMPTS = 6
    MAX_CANDIDATES = 3

    # ------------------------------------------------------------------
    # Entry point, called from Core.resolveit after the GUID has been resolved
    # ------------------------------------------------------------------
    def self.resolve_oaipmh(guid, meta)
      entries = entry_urls(guid, meta)
      return meta if entries.empty?

      meta.comments << "INFO: Looking for an OAI-PMH endpoint for #{entries.last}.\n"
      endpoint = nil
      identify = nil
      hinted_identifier = nil

      catalog_urls = fairicat_catalog_urls(meta, entries)
      catalog_urls.each do |catalog_url|
        meta.comments << "INFO: Reading FAIRiCat catalog #{catalog_url}.\n"
        candidates = endpoints_from_fairicat(catalog_url, meta)
        endpoint, identify = first_valid_endpoint(candidates, meta, "FAIRiCat")
        break if endpoint
      end
      meta.comments << "INFO: No FAIRiCat catalog declaring an OAI-PMH endpoint was found.\n" unless endpoint

      unless endpoint
        candidates = heuristic_endpoints(meta)
        hinted_identifier = candidates.to_h { |c| [c[:endpoint], c[:identifier]] }
        endpoint, identify = first_valid_endpoint(candidates.map { |c| c[:endpoint] }, meta, "heuristic guess")
        meta.comments << "INFO: No OAI-PMH endpoint could be identified from the links of this resource.\n" unless endpoint
      end
      return meta unless endpoint

      harvest_record(endpoint, identify, guid, meta, entries, hinted_identifier && hinted_identifier[endpoint])
      meta
    rescue StandardError => e
      warn "OAI-PMH harvesting failed: #{e.class} #{e.message}"
      meta.comments << "WARN: OAI-PMH harvesting stopped after an unexpected error (#{e.class}: #{e.message}).\n"
      meta
    end

    # ------------------------------------------------------------------
    # Discovery: where might the resource (and therefore its repository) be?
    # ------------------------------------------------------------------
    def self.entry_urls(guid, meta)
      urls = meta.finalURI.to_a.dup
      urls << guid if guid.to_s.match?(%r{\Ahttps?://}i)
      urls.map(&:to_s).select { |u| u.match?(%r{\Ahttps?://}i) }
          .reject { |u| resolver?(u) }.uniq
    end

    def self.resolver?(url)
      host = URI.parse(url).host.to_s.downcase
      RESOLVER_HOSTS.any? { |r| host == r || host.end_with?(".#{r}") }
    rescue URI::Error
      false
    end

    def self.origin(url)
      uri = URI.parse(url)
      "#{uri.scheme}://#{uri.authority}"
    end

    # ------------------------------------------------------------------
    # Strategy 1: FAIRiCat
    # ------------------------------------------------------------------
    def self.fairicat_catalog_urls(meta, entry_urls)
      declared = meta.link_hints.select { |h| fairicat_link?(h) }.map { |h| h[:href] }
      well_known = entry_urls.map { |u| "#{origin(u)}/.well-known/api-catalog" }
      (declared + well_known).uniq.first(MAX_CANDIDATES + 1)
    end

    def self.fairicat_link?(hint)
      hint[:rels].include?("api-catalog") &&
        (hint[:type].nil? || hint[:type].to_s.downcase.start_with?(FAIRICAT_TYPE))
    end

    # @return [Array<String>] OAI-PMH endpoint URLs declared by the catalog, best first
    def self.endpoints_from_fairicat(catalog_url, meta)
      # meta: nil keeps Core.fetch from logging a WARN: most hosts have no catalog, and that is normal
      head, body = Core.fetch(guid: catalog_url, headers: { "Accept" => FAIRICAT_TYPE }, meta: nil)
      unless head && body
        meta.comments << "INFO: No FAIRiCat catalog could be retrieved from #{catalog_url}.\n"
        return []
      end

      endpoints_from_linkset(JSON.parse(body))
    rescue JSON::ParserError
      meta.comments << "WARN: #{catalog_url} is not valid JSON, so it cannot be a FAIRiCat linkset.\n"
      []
    end

    def self.endpoints_from_linkset(doc)
      entries = doc.is_a?(Hash) ? Array(doc["linkset"]) : []
      entries.filter_map do |entry|
        next unless entry.is_a?(Hash)

        targets = SERVICE_RELS.flat_map { |rel| Array(entry[rel]) }.filter_map { |t| t["href"] if t.is_a?(Hash) }
        next unless targets.any? { |href| oai_spec_or_identify?(href) }

        # the anchor is the service endpoint; fall back to a verb URL among the targets
        anchor = entry["anchor"].to_s
        verb_url = targets.find { |href| href.match?(VERB_QUERY) || href.to_s.include?("verb=") }
        normalise_endpoint(anchor.empty? ? verb_url : anchor)
      end.uniq
    end

    def self.oai_spec_or_identify?(href)
      href.to_s.match?(SPEC_URL) || href.to_s.match?(/verb=Identify/)
    end

    # ------------------------------------------------------------------
    # Strategy 2: heuristics over links we have already seen
    # ------------------------------------------------------------------
    # @return [Array<Hash>] {endpoint:, identifier:, score:}, most convincing first
    def self.heuristic_endpoints(meta)
      found = {}
      meta.link_hints.each do |hint|
        href = hint[:href]
        score = if URI.parse(href).query.to_s.match?(VERB_QUERY) then 2
                elsif URI.parse(href).path.to_s.match?(PATH_NAME) then 1
                else next
                end
        endpoint = normalise_endpoint(href)
        next unless endpoint

        identifier = query_params(href)["identifier"]
        current = found[endpoint]
        if current.nil? || score > current[:score]
          found[endpoint] = { endpoint: endpoint, identifier: identifier || current&.dig(:identifier), score: score }
        elsif identifier && !current[:identifier]
          current[:identifier] = identifier
        end
      end
      found.values.sort_by { |c| -c[:score] }.first(MAX_CANDIDATES)
    rescue URI::Error
      []
    end

    def self.query_params(url)
      URI.decode_www_form(URI.parse(url).query.to_s).to_h
    rescue URI::Error, ArgumentError
      {}
    end

    # drop the query and fragment: an endpoint is the base URL that verbs are added to
    def self.normalise_endpoint(url)
      return nil if url.to_s.strip.empty?

      uri = URI.parse(url.to_s.strip)
      return nil unless %w[http https].include?(uri.scheme)

      uri.query = nil
      uri.fragment = nil
      uri.to_s
    rescue URI::Error
      nil
    end

    # ------------------------------------------------------------------
    # Verification
    # ------------------------------------------------------------------
    # @return [Array(String, Nokogiri::XML::Document)] first endpoint answering Identify, or nil
    def self.first_valid_endpoint(candidates, meta, source)
      candidates.first(MAX_CANDIDATES).each do |endpoint|
        meta.comments << "INFO: Testing #{endpoint} (from #{source}) with an OAI-PMH Identify request.\n"
        doc = identify(endpoint, meta)
        if doc
          meta.comments << "INFO: #{endpoint} is a valid OAI-PMH server (found via #{source}).\n"
          return [endpoint, doc]
        end
        meta.comments << "INFO: #{endpoint} did not answer as an OAI-PMH server.\n"
      end
      nil
    end

    def self.identify(endpoint, meta)
      doc = oai_request(endpoint, { "verb" => "Identify" }, meta)
      doc if doc&.at_xpath("/OAI-PMH/Identify")
    end

    # @return [Nokogiri::XML::Document, nil] namespace-stripped OAI-PMH response, or nil if the
    #   request failed or the body is not an OAI-PMH document
    def self.oai_request(endpoint, params, meta)
      url = "#{endpoint}#{endpoint.include?("?") ? "&" : "?"}#{URI.encode_www_form(params)}"
      _head, body = Core.fetch(guid: url, headers: XML_ACCEPT, meta: nil)
      return nil unless body

      doc = Nokogiri::XML(body) { |config| config.nonet.strict }
      doc.remove_namespaces!
      doc.at_xpath("/OAI-PMH") ? doc : nil
    rescue Nokogiri::XML::SyntaxError
      meta.comments << "INFO: the response from #{endpoint} was not well-formed XML.\n"
      nil
    end

    # ------------------------------------------------------------------
    # Harvesting
    # ------------------------------------------------------------------
    def self.harvest_record(endpoint, identify, guid, meta, entries, hinted_identifier)
      name = identify.at_xpath("/OAI-PMH/Identify/repositoryName")&.text
      meta.comments << "INFO: OAI-PMH repository '#{name}' at #{endpoint}.\n" if name

      subject = entries.last || guid
      prefixes = metadata_prefixes(endpoint, meta)
      identifier = nil
      record_doc = nil

      (([hinted_identifier].compact + identifier_candidates(identify, guid, entries)).uniq).first(MAX_IDENTIFIER_ATTEMPTS).each do |candidate|
        record_doc = oai_request(endpoint, { "verb" => "GetRecord", "identifier" => candidate, "metadataPrefix" => "oai_dc" }, meta)
        if record_doc&.at_xpath("/OAI-PMH/GetRecord/record")
          identifier = candidate
          break
        end
        record_doc = nil
      end

      unless identifier
        meta.comments << "INFO: #{endpoint} is an OAI-PMH server, but none of the identifiers that can be derived from #{guid} matched a record there. " \
                         "Publish the record's OAI identifier (e.g. an OAI-PMH GetRecord link in a Link header) to allow harvesting.\n"
        return
      end

      meta.comments << "INFO: Found OAI-PMH record #{identifier}; harvesting oai_dc metadata.\n"
      merge_record(record_doc, subject, meta)

      extra = (PREFERRED_PREFIXES & prefixes).first
      return unless extra

      meta.comments << "INFO: Also harvesting the '#{extra}' metadata format offered by #{endpoint}.\n"
      extra_doc = oai_request(endpoint, { "verb" => "GetRecord", "identifier" => identifier, "metadataPrefix" => extra }, meta)
      merge_record(extra_doc, subject, meta) if extra_doc&.at_xpath("/OAI-PMH/GetRecord/record")
    end

    def self.metadata_prefixes(endpoint, meta)
      doc = oai_request(endpoint, { "verb" => "ListMetadataFormats" }, meta)
      return [] unless doc

      doc.xpath("//metadataFormat/metadataPrefix").map { |n| n.text.strip }
    end

    # Candidate OAI identifiers, most likely first. OAI identifiers are
    # repository-specific, but the oai-identifier description (and its sample)
    # tells us the scheme, and the tail is usually the local id / DOI.
    def self.identifier_candidates(identify, guid, entry_urls)
      sample = identify.at_xpath("//oai-identifier/sampleIdentifier")&.text&.strip
      repo_id = identify.at_xpath("//oai-identifier/repositoryIdentifier")&.text&.strip
      delimiter = identify.at_xpath("//oai-identifier/delimiter")&.text&.strip
      delimiter = ":" if delimiter.to_s.empty?
      prefix = if sample && sample.include?(delimiter)
                 sample[0..sample.rindex(delimiter)]
               elsif repo_id
                 "oai#{delimiter}#{repo_id}#{delimiter}"
               end

      last_segment = entry_urls.map { |u| File.basename(URI.parse(u).path.to_s) rescue nil }.compact.reject(&:empty?)
      locals = last_segment.map { |s| URI.decode_www_form_component(s) }
      locals += locals.filter_map { |s| s[/(\d+)\z/, 1] }
      doi = guid.to_s[%r{10\.\d{4,9}/\S+}]
      locals += [doi, doi&.sub(%r{\A[^/]+/}, "")].compact

      ids = prefix ? locals.map { |l| "#{prefix}#{l}" } : []
      (ids + [guid.to_s] + entry_urls).uniq
    end

    # ------------------------------------------------------------------
    # Turning OAI-PMH records into harvested metadata
    # ------------------------------------------------------------------
    def self.merge_record(doc, subject, meta)
      metadata = doc.at_xpath("/OAI-PMH/GetRecord/record/metadata")
      return unless metadata

      if (rdf = metadata.at_xpath("./*[local-name()='RDF']"))
        meta.comments << "INFO: The OAI-PMH record contains RDF/XML; parsing as linked data.\n"
        Core.parse_rdf(meta, rdf.to_xml, "application/rdf+xml")
      elsif (dc = metadata.at_xpath("./dc"))
        triples = dc_triples(dc, subject)
        meta.comments << "INFO: Parsed #{triples.size} Dublin Core statements from the OAI-PMH record.\n"
        meta.merge_rdf(triples)
      elsif (root = metadata.element_children.first)
        meta.comments << "INFO: The OAI-PMH record uses the '#{root.name}' format; adding it to the metadata hash.\n"
        meta.merge_hash(XmlSimple.xml_in(root.to_xml, "ForceArray" => false))
      end
    end

    def self.dc_triples(dc, subject)
      subj = RDF::URI(subject)
      dc.element_children.filter_map do |el|
        value = el.text.strip
        next if value.empty?

        object = value.match?(%r{\Ahttps?://\S+\z}) && %w[identifier relation source].include?(el.name) ? RDF::URI(value) : RDF::Literal(value)
        RDF::Statement.new(subj, RDF::URI("#{DC_NS}#{el.name}"), object)
      end
    end
  end
end
