HARVESTER_VERSION = "Hvst-1.5.0".freeze
# better output,
# different dealing with DataCite (they have a unique type header)
# handle large extruct output,
# deal correctly with unknown identifier types

# def URI.escape(g)  # monkey patch to bring back functionality for metainspector
#   URI::Parser.new.escape(g)
# end

# def URI.encode(g)  # monkey patch to bring back functionality for metainspector
#   URI::Parser.new.escape(g)
# end

module FAIRChampionHarvester
  class Core
    @@distillerknown = {} # global, hash of sha256 keys of message bodies - have they been seen before t/f

    def self.resolveit(guid)
      # if meta = FAIRChampionHarvester::Utils::retrieveMetaObject(guid)
      #    return meta
      # end

      meta = FAIRChampionHarvester::MetadataObject.new

      FAIRChampionHarvester::Utils::GUID_TYPES.each do |pair| # meta object gets updated in each case
        k, regex = pair
        if k == "inchi" and regex.match(guid)
          FAIRChampionHarvester::INCHI.resolve_inchi(guid, meta)
        elsif k == "handle1" and regex.match(guid)
          FAIRChampionHarvester::Handle.resolve_handle(guid, meta)
        elsif k == "handle2" and regex.match(guid)
          FAIRChampionHarvester::Handle.resolve_handle(guid, meta)
        elsif k == "uri" and regex.match(guid)
          FAIRChampionHarvester::Uri.resolve_uri(guid, meta)
        elsif k == "doi" and regex.match(guid)
          FAIRChampionHarvester::DOI.resolve_doi(guid, meta)
        end
      end

      if meta.comments.empty? # didn't match any of the types, so no comments were added
        meta.guidtype = "unknown"
        meta.comments << "CRITICAL: The guid '#{guid}' did not correspond to any known GUID format. Tested #{FAIRChampionHarvester::Utils::GUID_TYPES.keys}. Halting.\n"
      end
      meta.comments << "INFO: END OF HARVESTING\n"
      # FAIRChampionHarvester::Utils::cacheMetaObject(meta, guid)
      meta
    end

    def self.convertToURL(guid)
      FAIRChampionHarvester::Utils::GUID_TYPES.each do |pair|
        k, regex = pair
        if k == "inchi" and regex.match(guid)
          return "inchi", "https://pubchem.ncbi.nlm.nih.gov/rest/rdf/inchikey/#{guid}"
        elsif k == "handle1" and regex.match(guid)
          return "handle", "http://hdl.handle.net/#{guid}"
        elsif k == "handle2" and regex.match(guid)
          return "handle", "http://hdl.handle.net/#{guid}"
        elsif k == "uri" and regex.match(guid)
          return "uri", guid
        elsif k == "doi" and regex.match(guid)
          return "doi", "https://doi.org/#{guid}"
        elsif k == "ark_url" and regex.match(guid)
          return "ark_url", guid
        elsif k == "ark" and regex.match(guid)
          return "ark", "https://n2t.net/#{guid}"
        end
      end
      [nil, nil]
    end

    def self.typeit(guid)
      FAIRChampionHarvester::Utils::GUID_TYPES.each do |pair|
        type, regex = pair
        return type if regex.match(guid)
      end
      false
    end

    # ==================================================================
    # ==================================================================
    # ==================================================================
    # ==================================================================
    # ==================================================================

    def self.parse_text(meta, body)
      meta.comments << "WARTN: Plain Text cannot be mapped to any parser.  No structured metadata found.\n"
      meta.comments << "INFO: Using Apache Tika to attempt to extract metadata from plaintext.\n"

      FAIRChampionHarvester::Tika.do_tika(meta, body)
    end

    def self.parse_json(meta, body)
      hash = JSON.parse(body)
      # warn body
      # warn hash.inspect
      # warn hash.class

      meta.hash.merge!(hash)
      #      warn meta.hash
      meta.hash
    end

    def self.parse_html(meta, body)
      # just use extruct and distiller instead
    end

    def self.parse_rdf(meta, body, format = nil)
      unless body
        meta.comments << "CRITICAL: The response message body component appears to have no content.\n"
        return meta
      end
      unless body.match(/\w/)
        meta.comments << "CRITICAL: The response message body component appears to have no content.\n"
        return meta
      end

      warn "\n\n\nSANITY CHECK \n\n#{body[0..300]}\n\n"
      # sanitycheck = RDF::Format.for({ sample: body[0..5000] })
      # unless sanitycheck
      #   meta.comments << "CRITICAL: The Evaluator found what it believed to be RDF (sample:  #{body[0..300].delete!("\n")}), but it could not find a parser.  Please report this error, along with the GUID of the resource, to the maintainer of the system.\n"
      #   return meta
      # end

      graph = FAIRChampionHarvester::Cache.checkRDFCache(body)
      if graph.size > 0
        warn "\n\n\n unmarshalling graph from cache\n\n"
        warn "\n\ngraph size #{graph.size} #{graph.inspect}\n\n"
        meta.merge_rdf(graph.to_a)
        return meta
      end

      formattype = nil
      warn "\n\n\ndeclared format #{format}\n\n"
      if format.nil?
        formattype = RDF::Format.for({ sample: body[0..3000] })
        warn "\n\n\ndetected format #{formattype}\n\n"
      else
        warn "\n\n\ntesting declared format #{format}\n\n"
        formattype = RDF::Format.for(content_type: format)
        warn "\n\n\nfound format #{formattype}\n\n"
      end
      warn "\n\n\nfinal format #{formattype}\n\n"
      # $stderr.puts "\n\n\nBODY #{body}\n\n"

      unless formattype
        meta.comments << "CRITICAL: Unable to find an RDF reader type that matches the content that was returned from resolution.  Here is a sample #{body[0..100]}  Please send your GUID to the dev team so we can investigate!\n"
        return meta
      end
      meta.comments << "INFO: The response message body component appears to contain #{formattype}.\n"
      reader = ""
      begin
        reader = formattype.reader.new(body)
      rescue StandardError
        meta.comments << "WARN: Though linked data was found, it failed to parse.  This likely indicates some syntax error in the data.  As a result, no metadata will be extracted from this message.\n"
        return meta
      end

      begin
        # $stderr.puts "Reader Class #{reader.class}\n\n #{reader.inspect}"
        if reader.size == 0
          meta.comments << "WARN: Though linked data was found, it failed to parse.  This likely indicates some syntax error in the data.  As a result, no metadata will be extracted from this message.\n"
          return meta
        end
        #       reader.rewind!
        # for some reason, the rewind method isn't working here...??
        reader = formattype.reader.new(body) # have to re-read it here, but now its safe because we have already caught errors
        warn "WRITING TO CACHE"
        FAIRChampionHarvester::Cache.writeRDFCache(reader, body) # write to the special RDF graph cache
        warn "WRITING DONE"
        reader = formattype.reader.new(body)
        warn "RE-READING DONE"
        meta.merge_rdf(reader.to_a)
        warn "MERGE DONE"
      rescue RDF::ReaderError => e
        meta.comments << "CRITICAL: The Linked Data was malformed and caused the parser to crash with error message: #{e.message} ||  (sample of what was parsed:  #{body[0..300].delete("\n")})\n"
        warn "CRITICAL: The Linked Data was malformed and caused the parser to crash with error message: #{e.message} ||  (sample of what was parsed:  #{body[0..300].delete("\n")})\n"
        nil
      rescue Exception => e
        meta.comments << "CRITICAL: An unknown error occurred while parsing the (apparent) Linked Data (sample of what was parsed:  #{body[0..300].delete("\n")}).  Moving on...\n"
        warn "\n\nCRITICAL: #{e.inspect} An unknown error occurred while parsing the (apparent) Linked Data (full body:  #{body}).  Moving on...\n\n"
        nil
      end
    end

    def self.parse_xml(meta, body)
      hash = XmlSimple.xml_in(body)
      meta.comments << "INFO: The XML is being converted into a simple hash structure.\n"
      meta.hash.merge hash
      meta.hash
    end

    def self.parse_link_http_headers(headers)
      # we can be sure that a Link header is a URL
      # code stolen from https://gist.github.com/thesowah/0ca5e1b4b3c61bfe8e13 with a few tweaks

      links = headers[:link]
      return [] unless links

      parts = links.split(",")

      urls = []
      # Parse each part into a named link
      parts.each do |part, _index|
        section = part.split(";")
        next unless section[0]

        url = section[0][/<(.*)>/, 1]
        next unless section[1]

        type = ""
        section[1..].each do |s|
          type = s[/rel="?(\w+)"?/, 1]
          break if type
        end
        next unless type
        # "meta" headers are for old versions of Virtuoso LDP - not in link relations standared
        next unless %w[meta alternate].include?(type.downcase)

        urls << url
      end
      urls
    end

    def self.parse_link_body_headers(url, body)
      # Parse the HTML body (Nokogiri is tolerant of malformed HTML)
      doc = Nokogiri::HTML(body)

      # Focus on <link> tags inside <head> (MetaInspector's head_links equivalent)
      # We use css selector for simplicity and readability
      link_nodes = doc.css('head link[rel="alternate"][type]') # only those with rel=alternate AND type attr

      # Your format lists – assuming these are constants/hashes like:
      # FAIRChampionHarvester::Utils::RDF_FORMATS  => { jsonld: "application/ld+json", ... }
      # We flatten them once for efficiency
      allowed_types = [
        FAIRChampionHarvester::Utils::RDF_FORMATS.values,
        FAIRChampionHarvester::Utils::XML_FORMATS.values,
        FAIRChampionHarvester::Utils::JSON_FORMATS.values
      ].flatten.uniq # uniq to avoid duplicates if any overlap

      # Filter and extract hrefs
      urls = link_nodes.filter_map do |link|
        type = link["type"]&.strip
        next unless type && allowed_types.include?(type)

        href = link["href"]&.strip
        href if href && !href.empty?
      end

      # Optional: make relative URLs absolute (MetaInspector usually does this)
      base_uri = begin
        URI.parse(url)
      rescue StandardError
        nil
      end
      if base_uri
        urls.map! do |href|
          URI.join(base_uri, href).to_s
        rescue StandardError
          href
        end
      end

      warn "\n\nGOT BODY LINKS #{urls}\n\n"

      urls
    end
    # def self.parse_link_body_headers(url, body)
    #   m = MetaInspector.new(url, document: body)
    #   # accept any alternate that is in structured data format
    #   ls = m.head_links.select do |l|
    #     l[:rel] == 'alternate' and
    #       [FAIRChampionHarvester::Utils::RDF_FORMATS.values,
    #        FAIRChampionHarvester::Utils::XML_FORMATS.values,
    #        FAIRChampionHarvester::Utils::JSON_FORMATS.values].flatten
    #         .include?(l[:type])
    #   end
    #   # ls is an array of elements that look like this: [{:rel=>"alternate", :type=>"application/ld+json", :href=>"http://scidata.vitk.lv/dataset/303.jsonld"}]
    #   urls = ls.map { |l| l[:href] }
    #   urls.compact
    #   warn "\n\nGOT BODY LINKS #{urls}\n\n"
    #   urls
    # end

    # Recursively collects **all non-Hash values** (leaf values) from a nested Hash structure.
    #
    # Traverses the hash in depth-first order and gathers every value that is not itself
    # a Hash into a flat array. Keys are completely ignored.
    #
    # @param myHash [Hash] the nested hash to traverse
    # @param value  [Object] currently unused (likely legacy or placeholder parameter)
    # @param vals   [Array] accumulator for collected values (mutable, passed by reference)
    # @return [Array] flat list of all leaf (non-Hash) values in depth-first traversal order
    #
    # @example
    #   h = {
    #     name: "Alice",
    #     info: {
    #       age: 34,
    #       address: { city: "Madrid", coords: { lat: 40.4168, lon: -3.7038 } },
    #       hobbies: ["reading", "hiking"]
    #     }
    #   }
    #
    #   deep_dive_values(h)
    #   # => ["Alice", 34, "Madrid", 40.4168, -3.7038, "reading", "hiking"]
    #
    def self.deep_dive_values(myHash, value = nil, vals = [])
      myHash.each_pair do |_key, value|
        if value.is_a?(Hash)
          # $stderr.puts "key: #{_key} recursing..."   # uncomment for debugging
          deep_dive_values(value, value, vals)
        else
          vals << value
        end
      end

      vals
    end

    # Recursively collects **every key-value pair** from a nested Hash structure as [key, value] arrays.
    #
    # Traverses the entire nested hash in depth-first order and records every key-value pair
    # encountered — including pairs where the value is itself a Hash.
    #
    # Note: The `property` parameter is currently **not used** (dead code). Both branches
    # of the conditional do the same thing, so every pair is collected regardless of `property`.
    #
    # @param myHash   [Hash] the nested hash to traverse
    # @param property [Symbol, String, nil] intended filter key (currently ineffective)
    # @param props    [Array] accumulator for [key, value] pairs (mutable)
    # @return [Array<Array>] flat list of [key, value] tuples in depth-first order
    #
    # @example
    #   h = {
    #     user: "bob42",
    #     config: {
    #       theme: "dark",
    #       alerts: { email: true, push: false }
    #     }
    #   }
    #
    #   deep_dive_properties(h)
    #   # => [[:user, "bob42"],
    #   #     [:config, {theme: "dark", alerts: {email: true, push: false}}],
    #   #     [:theme, "dark"],
    #   #     [:alerts, {email: true, push: false}],
    #   #     [:email, true],
    #   #     [:push, false]]
    #
    #   deep_dive_properties(h, :email)   # ← currently returns the same as above (bug)
    #
    def self.deep_dive_properties(myHash, property = nil, props = [])
      return props unless myHash.is_a?(Hash)

      myHash.each_pair do |key, value|
        # The conditional is redundant — both branches are identical
        # This is very likely a bug or unfinished implementation.
        props << if property && property == key
                   [key, value]
                 else
                   [key, value]
                 end

        if value.is_a?(Hash)
          # $stderr.puts "key: #{key} recursing..."   # uncomment for debugging
          deep_dive_properties(value, property, props)
        end
      end

      props
    end

    def self.figure_out_type(head)
      type = head[:content_type]
      if type.nil?
        warn "\n\nSTRANGE - headers had no content-type\n\n"
        return nil, nil
      end
      type.match(%r{([\w+.]+/[\w+.]+):?;?}im)
      type = ::Regexp.last_match(1)
      # $stderr.puts "\n\nsearching for #{type}\n\n"

      FAIRChampionHarvester::Utils::RDF_FORMATS.each do |parser, types|
        return parser, type if types.include? type
      end
      FAIRChampionHarvester::Utils::JSON_FORMATS.each do |parser, types|
        return parser, type if types.include? type
      end
      FAIRChampionHarvester::Utils::TEXT_FORMATS.each do |parser, types|
        return parser, type if types.include? type
      end
      FAIRChampionHarvester::Utils::XML_FORMATS.each do |parser, types|
        return parser, type if types.include? type
      end
      FAIRChampionHarvester::Utils::HTML_FORMATS.each do |parser, types|
        return parser, type if types.include? type
      end
      [nil, nil]
    end

    def self.fetch(guid:, headers: FAIRChampionHarvester::Utils::AcceptHeader, meta: nil) # we will try to retrieve turtle whenever possible
      head, body, finalURI = FAIRChampionHarvester::Cache.checkCache(guid, headers)
      return false if head and head == "ERROR"

      meta.finalURI |= [finalURI] if meta && finalURI

      warn meta.finalURI.inspect if meta
      if head and body
        warn "Retrieved from cache, returning data to code"
        return [head, body]
      end

      warn "In fetch routine now.  "
      begin
        warn "executing call over the Web to #{guid}"
        # response = RestClient::Request.execute(
        #   method: :get,
        #   url: guid.to_s,
        #   # user: user,
        #   # password: pass,
        #   headers: headers
        # )
        response = HTTP
                   .headers(headers).follow
                   .get(guid.to_s) # or full URL

        if response.status.success?
          final_url = response.uri.to_s
          meta.finalURI |= [final_url] if meta
          warn "There was a response to the call #{guid}"
          FAIRChampionHarvester::Cache.writeToCache(guid, headers, response.headers, response.body.to_s,
                                                    response.uri.to_s)
          [response.headers, response.body.to_s] # return headers, body, and final URL
        else
          # Handle HTTP error status codes (4xx, 5xx, etc.)
          warn "HTTP Error #{response.status} for #{url}"
          warn "Final URL: #{response.uri}" if response.uri
          FAIRChampionHarvester::Cache.writeErrorToCache(guid, headers)
          meta.comments << "WARN: HTTP error #{response.status} encountered when trying to resolve #{guid}\n" if meta
          false
        end
      rescue HTTP::Error => e
        # This catches network errors, timeouts, connection failures, DNS errors, etc.
        warn "HTTP Request Failed for #{guid}: #{e.message}"
        FAIRChampionHarvester::Cache.writeErrorToCache(guid, headers)
        meta.comments << "WARN: HTTP error #{e.message} encountered when trying to resolve #{guid}\n" if meta
        false
      rescue StandardError => e
        # Catch any other unexpected errors
        warn "Unexpected error while fetching #{guid}: #{e.class} - #{e.message}"
        warn e.backtrace.first(5).join("\n") if ENV["DEBUG"]
        FAIRChampionHarvester::Cache.writeErrorToCache(guid, headers)
        meta.comments << "WARN: HTTP error #{e.message} encountered when trying to resolve #{guid}\n" if meta
        false
      end
      # rescue RestClient::ExceptionWithResponse => e
      #   warn "ERROR! #{e.response}"
      #   FAIRChampionHarvester::Cache.writeErrorToCache(guid, headers)
      #   meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{guid}\n" if meta
      #   false
      #   # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      # rescue RestClient::Exception => e
      #   warn "ERROR! #{e}"
      #   meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{guid}\n" if meta
      #   FAIRChampionHarvester::Cache.writeErrorToCache(guid, headers)
      #   false
      #   # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      # rescue Exception => e
      #   warn "ERROR! #{e}"
      #   meta.comments << "WARN: HTTP error #{e} encountered when trying to resolve #{guid}\n" if meta
      #   FAIRChampionHarvester::Cache.writeErrorToCache(guid, headers)
      #   false
      #   # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      # end # you can capture the Exception and do something useful with it!\n",
    end

    def self.simplefetch(url, headers = FAIRChampionHarvester::Utils::AcceptHeader, _meta = nil) # we will try to retrieve turtle whenever possible
      # head = FAIRChampionHarvester::Utils::head(url, headers)
      # $stderr.puts "content length " + head[:content_length].to_s
      # if head[:content_length] and head[:content_length].to_f > 300000 and meta
      #    meta.comments << "WARN: The size of the content at #{url} reports itself to be >300kb.  This service will not download something so large.  This does not mean that the content is not FAIR, only that this service will not test it.  Sorry!\n"
      #    return false
      # end

      response = HTTP
                 .headers(headers).follow
                 .get(guid.to_s) # or full URL

      if response.status.success?
        [response.headers, response.body.to_s] # return headers, body, and final URL
      else
        # Handle HTTP error status codes (4xx, 5xx, etc.)
        warn "HTTP Error #{response.status} for #{url}"
        warn "Final URL: #{response.uri}" if response.uri
        false
      end
    rescue HTTP::Error => e
      # This catches network errors, timeouts, connection failures, DNS errors, etc.
      warn "HTTP Request Failed for #{guid}: #{e.message}"
      false
    rescue StandardError => e
      # Catch any other unexpected errors
      warn "Unexpected error while fetching #{guid}: #{e.class} - #{e.message}"
      false
    end

    # this returns the URI that results from all redirects, etc.
    def self.head(url, headers = FAIRChampionHarvester::Utils::AcceptHeader)
      response = RestClient::Request.execute({
                                               method: :head,
                                               url: url.to_s,
                                               # user: user,
                                               # password: pass,
                                               headers: headers
                                             })
      response.headers
    rescue RestClient::ExceptionWithResponse => e
      warn e.response
      false
    # now we are returning 'False', and we will check that with an \"if\" statement in our main code
    rescue RestClient::Exception => e
      warn e.response
      false
    # now we are returning 'False', and we will check that with an \"if\" statement in our main code
    rescue Exception => e
      warn e
      false
      # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      # you can capture the Exception and do something useful with it!\n",
    end

    # this returns the URI that results from all redirects, etc.
    def self.resolve(url, headers = FAIRChampionHarvester::Utils::AcceptHeader)
      response = RestClient::Request.execute({
                                               method: :head,
                                               url: url.to_s,
                                               # user: user,
                                               # password: pass,
                                               headers: headers
                                             })
      response.request.url
    rescue RestClient::ExceptionWithResponse => e
      warn e.response
      false
    # now we are returning 'False', and we will check that with an \"if\" statement in our main code
    rescue RestClient::Exception => e
      warn e.response
      false
    # now we are returning 'False', and we will check that with an \"if\" statement in our main code
    rescue Exception => e
      warn e
      false
      # now we are returning 'False', and we will check that with an \"if\" statement in our main code
      # you can capture the Exception and do something useful with it!\n",
    end

    # there is a need to map between a test and its registered Metric in FS.  This will return the label for the test
    # in principle, we cojuld return a more complex object, but all I need now is the label
    def self.get_tests_metrics(tests:)
      base_url = ENV["TEST_BASE_URL"] || "http://localhost:8282" # Default to local server
      test_path = ENV["TEST_PATH"] || "community-tests" # Default to local server
      labels = {}
      landingpages = {}
      tests.each do |testid|
        warn "getting dcat for #{testid}    #{base_url}/#{test_path}/#{testid}"
        dcat = RestClient::Request.execute({
                                             method: :get,
                                             url: "#{base_url}/#{test_path}/#{testid}",
                                             headers: { "Accept" => "application/json" }
                                           }).body
        parseddcat = JSON.parse(dcat)
        jpath = JsonPath.new('[0]["http://semanticscience.org/resource/SIO_000233"][0]["@id"]') # is implementation of
        metricurl = jpath.on(parseddcat).first

        begin
          g = RDF::Graph.load(metricurl, format: :turtle)
        rescue StandardError => e
          warn "DCAT Metric loading failed #{e.inspect}"
          g = RDF::Graph.new
        end

        title = g.query([nil, RDF::Vocab::DC.title, nil])&.first&.object&.to_s
        lp = g.query([nil, RDF::Vocab::DCAT.landingPage, nil])&.first&.object&.to_s

        labels[testid] = if title != ""
                           title
                         else
                           "Metric label not available"
                         end
        landingpages[testid] = if lp != ""
                                 lp
                               else
                                 ""
                               end
      end
      [labels, landingpages]
    end
  end # END OF Harvester CLASS
end
