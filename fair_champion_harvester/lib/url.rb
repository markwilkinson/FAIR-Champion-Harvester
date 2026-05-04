module FAIRChampionHarvester
  class URL
    def self.resolve_url(guid:, meta:, nolinkheaders: false, headers: FAIRChampionHarvester::Utils::AcceptHeader)
      meta.guidtype = "uri" if meta.guidtype.nil?
      warn "\n\n FETCHING #{guid} #{headers}\n\n"
      head, body = Core.fetch(guid: guid, headers: headers, meta: meta)
      unless head
        meta.comments << "WARN: Unable to resolve #{guid} using HTTP Accept header #{headers}.\n"
        return meta
      end

      meta.comments << "INFO: following redirection using this header led to the following URL: #{meta.finalURI.last}.  Using the output from this URL for the next few tests..."
      meta.full_response << body

      links = []
      links << Core.parse_link_http_headers(head) unless nolinkheaders
      links << Core.parse_link_body_headers(guid, body) unless nolinkheaders
      links.flatten!
      links.compact!
      warn "\n\n\nLINKS TO FOLLOW: #{links}\n\n\n"
      links.each do |link|
        meta.comments << "INFO: a Link 'alternate' or 'meta' header was found: #{link}, and is now being followed as an independent URI that may contain metadata.\n"
        FAIRChampionHarvester::URL.resolve_url(guid: link, meta: meta, nolinkheaders: true) # the true is to prevent recursive pursuit of link headers
        meta.comments << "INFO: parsing of Link #{link} complete.\n"
      end # this fills the metadata object with the content from Link headers, but not recursively
      meta.comments << "INFO: Link Header and Meta Link parsing complete.  Back in main thread.\n"

      parser, contenttype = Core.figure_out_type(head)

      meta.comments << "INFO: Found #{parser} #{contenttype} type of content when resolving #{guid} using HTTP Accept header #{headers}.\n"
      warn "\n\nFound #{parser} type of file by resolving GUID #{guid}. \n\n"

      #  DO SAMPLING FIRSY TO FIND A MATCH

      if FAIRChampionHarvester::Utils::TEXT_FORMATS.keys.include?(parser)
        warn "\n\nPARSING TEXT\n\n"
        meta.comments << "INFO: parsing as plaintext. \n"
        Core.parse_text(meta, body)
      elsif FAIRChampionHarvester::Utils::RDF_FORMATS.keys.include?(parser)
        warn "\n\nPARSING RDF\n\n"
        meta.comments << "INFO: parsing as linked data. \n"
        if contenttype == "application/trig"
          Core.parse_rdf(meta, body, contenttype)
        else
          Core.parse_rdf(meta, body)
        end
      elsif FAIRChampionHarvester::Utils::HTML_FORMATS.keys.include?(parser)
        meta.comments << "INFO: parsing as HTML. \n"
        warn "\n\nPARSING HTML\n\n"
        url = if meta.finalURI.last =~ %r{^\w+://}
                meta.finalURI.last
              else
                guid
              end
        meta.comments << "INFO: Now attempting to use the extruct parser. \n"
        FAIRChampionHarvester::Extruct.do_extruct(meta, url, content_type: head[:content_type], body_prefix: body[0, 8])
        meta.comments << "INFO: Now attempting to use the Kellogg's Distiller parser. \n"
        meta.comments << "INFO: Note that, if the Distiller fails, you can view the output of its parse by visiting http://rdf.greggkellogg.net/distiller?command=serialize&url=#{CGI.escape(url.to_s)}. \n"
        FAIRChampionHarvester::Distiller.do_distiller(meta, body)
      elsif FAIRChampionHarvester::Utils::XML_FORMATS.keys.include?(parser)
        meta.comments << "INFO: parsing as XML. \n"
        warn "\n\nPARSING XML\n\n"
        Core.parse_xml(meta, body)
      elsif FAIRChampionHarvester::Utils::JSON_FORMATS.keys.include?(parser)
        meta.comments << "INFO: parsing as JSON. \n"
        warn "\n\nPARSING JSON\n\n"
        Core.parse_json(meta, body)
      else
        meta.comments << "INFO: Body of the message did not match known structured data types. \n"
        warn "\n\nPARSING UNKNOWN\n\n"
        url = if meta.finalURI.last =~ %r{^\w+://}
                meta.finalURI.last
              else
                guid
              end
        warn "\n\nPARSING UNKNOWN from #{url}\n\n"
        meta.comments << "WARN: parser could not be found. \n"
        warn "\n\nPARSING WITH TIKA\n\n"
        meta.comments << "INFO:  Metadata may be embedded, now searching using the Apache 'tika' tool.\n"
        FAIRChampionHarvester::Tika.do_tika(meta, body) # this expects a string, not an Net::HTTP
        warn "\n\nPARSING WITH DISTILLER\n\n"
        meta.comments << "INFO:  Metadata may be embedded, now searching using the 'Distiller' tool.\n"
        FAIRChampionHarvester::Distiller.do_distiller(meta, body)
        warn "\n\nPARSING WITH EXTRUCT\n\n"
        meta.comments << "INFO: Metadata may be embedded, now searching using the 'extruct' tool.\n"
        FAIRChampionHarvester::Extruct.do_extruct(meta, url, content_type: head[:content_type], body_prefix: body[0, 8])
      end

      meta
    end
  end
end
