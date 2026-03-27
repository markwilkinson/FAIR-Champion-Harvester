module FAIRChampionHarvester
  class INCHI
    def self.resolve_inchi(guid, meta)
      type, url = Core.convertToURL(guid)
      meta.guidtype = type if meta.guidtype.nil?
      meta.comments << "INFO: Found an InChI Key GUID.\n"
      # $stderr.puts "1"
      meta.comments << "INFO: Resolving using PubChem Resolver #{url} with HTTP Accept Headers #{FAIRChampionHarvester::Utils::AcceptHeader}.\n"

      head, body = Core.fetch(guid: url, headers: FAIRChampionHarvester::Utils::AcceptHeader, meta: meta)
      # this is a Net::HTTP response
      # $stderr.puts "2"

      return meta unless body

      # $stderr.puts "3"

      meta.full_response << body # set it here so it isn't empty
      # $stderr.puts "4"

      (parser, type) = Core.figure_out_type(head)
      unless parser and type
        meta.comments << "CRITICAL: Couldn't find a parser for the data returned from #{url}. Halting. \n"
        return meta
      end
      # $stderr.puts "5"

      # this next operation is safe because we know that pubchem does in fact return Turtle
      unless parser.eql? "turtle"
        meta.comments << "CRITICAL: expected turtle format from #{url}. Halting. \n"
        return meta
      end
      # $stderr.puts "6"

      Core.parse_rdf(meta, body)

      query = SPARQL.parse("select ?o where {VALUES ?p {
                            <http://semanticscience.org/resource/is-attribute-of> <https://semanticscience.org/resource/is-attribute-of>}
                              ?s ?p ?o}")
      results = query.execute(meta.graph)
      unless results.any?
        meta.comments << "CRITICAL: Could not find the sio:is_attribute_of predicate in the first layer of metadatafrom https://pubchem.ncbi.nlm.nih.gov/rest/rdf/inchikey/#{guid}. Halting. \n"
        return meta
      end
      # $stderr.puts "7"

      cpd = results.first[:o]
      cpd = cpd.to_s
      cpd = cpd.gsub(%r{/$}, "") # has a rogue trailing slash
      meta.comments << "INFO: Found #{cpd} as the identifier of the second layer of metadata.\n"
      meta.comments << "INFO: Resolving #{cpd} using HTTP Accept Header #{FAIRChampionHarvester::Utils::AcceptHeader}.\n"

      head2, body2 = Core.fetch(guid: cpd, headers: FAIRChampionHarvester::Utils::AcceptHeader, meta: meta)
      unless body2
        meta.comments << "CRITICAL: Resolution of #{cpd} using HTTP Accept Header #{FAIRChampionHarvester::Utils::AcceptHeader} returned no message body. Halting. \n"
        return meta
      end
      # $stderr.puts "8"

      meta.full_response << body2 # set it here so it isn't empty
      (parser, type) = Harvester.figure_out_type(head2)
      # this next operation is safe because we know that pubchem does in fact return Turtle
      unless parser.eql? "turtle"
        meta.comments << "CRITICAL: Expected turtle format from #{cpd}.  Giving up. \n"
        return meta # simply fail if they asked for HTML or something else
      end
      # $stderr.puts "9"
      Harvester.parse_rdf(meta, body2)
      # $stderr.puts "10"

      meta
    end
  end
end
