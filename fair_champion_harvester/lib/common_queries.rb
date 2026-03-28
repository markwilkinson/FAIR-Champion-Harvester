module FAIRChampionHarvester
  class CommonQueries
    def self.GetSelfIdentifier(g, meta = FAIRChampionHarvester::MetadataObject.new)
      identifiers = []

      FAIRChampionHarvester::Utils::SELF_IDENTIFIER_PREDICATES.each do |prop|
        if prop =~ %r{schema\.org/identifier}
          # test 1 - this assumes that the identifier node attached to "root" is the one we are looking for
          # and assumes the PropertyValue schema for the value of identifier
          query = SPARQL.parse("select ?identifier where {
                                      VALUES ?predi {<http://schema.org/identifier> <https://schema.org/identifier>}
                                      VALUES ?predpv {<http://schema.org/PropertyValue> <https://schema.org/PropertyValue>}
                                      VALUES ?predval {<http://schema.org/value> <https://schema.org/value>}
                                      ?s ?predi ?i .
                                      ?i a ?predpv .
                                      ?i ?predval ?identifier .
                                      FILTER NOT EXISTS {?sub ?pred ?s} } #must be the root, if not, we don't know what id it is!
                  ")
          results = query.execute(g)
          if results.any?
            results.each do |r|
              unless r[:identifier].respond_to? :value
                meta.comments << "INFO: '#{prop}' PropertyValue did not have the expected structure.  Moving on.\n"
                next
              end

              identifier = r[:identifier].value
              meta.comments << "INFO: found identifier '#{identifier}' using Schema.org identifier as PropertyValue.\n"
              identifiers << identifier
            end
          else
            # g.each_statement {|s| $stderr.puts s.subject, s.predicate, s.object, "\n"}
            # test 2 - a simple URL or a value from schema
            # $stderr.puts "QUEWRY: select ?identifier where {?s <#{prop}> ?identifier}"
            query = SPARQL.parse("select ?identifier where {?s <#{prop}> ?identifier}")
            results = query.execute(g)
            if results.any?
              results.each do |r|
                # $stderr.puts "inspecting results from query #{r.inspect}"
                unless r[:identifier].respond_to? :value
                  meta.comments << "INFO: '#{prop}' as a simple value did not have the expected structure.  Moving on.\n"
                  next
                end
                identifier = r[:identifier].value
                meta.comments << "INFO: found identifier '#{identifier}' using Schema.org identifier as with a string or URI value.\n"
                identifiers << identifier
              end
            end
          end
        else
          query = SPARQL.parse("select ?identifier where {?s <#{prop}> ?identifier}")
          results = query.execute(g)
          if results.any?
            results.each do |r|
              unless r[:identifier].respond_to? :value
                meta.comments << "INFO: '#{prop}' as a simple identifier predicate did not have the expected structure.  Moving on.\n"
                next
              end
              identifier = r[:identifier].value
              meta.comments << "INFO: found identifier '#{identifier}' using #{prop} as a string or URI.\n"
              identifiers << identifier
            end
          end
        end
      end

      identifiers
    end

    def self.GetDataIdentifier(graph:, meta: FAIRChampionHarvester::MetadataObject.new) # send it the graph
      @identifier = nil
      g = graph
      # warn "querying graph of size #{g.size}"
      # warn "#{g.dump(:ntriples)}\n\n\n"
      meta.comments << "INFO: SPARQLing graph of size #{graph.size}.\n"

      FAIRChampionHarvester::Utils::DATA_PREDICATES.each do |prop|
        meta.comments << "INFO: SPARQLing for #{prop}.\n"
        if prop =~ %r{schema\.org/distribution}
          # query = SPARQL.parse("select ?o where {
          #                                 VALUES ?schemaurl {<http://schema.org/contentUrl> <https://schema.org/contentUrl>}
          #                                 VALUES ?dist {<http://schema.org/distribution> <https://schema.org/distribution>}
          #                                 ?s ?dist ?b .
          #                                 ?b  ?schemaurl ?o}")
          query = SPARQL.parse("select ?o where {

                                          VALUES ?dist {<http://schema.org/distribution> <https://schema.org/distribution>}
                                          ?s ?dist ?b .
                                          }")

          results = query.execute(g)
          if results.any?
            unless results.first[:o].respond_to? :value
              meta.comments << "INFO: '#{prop}' data identifier did not have the expected structure.  Moving on.\n"
              next
            end
            @identifier = results.first[:o].value
            meta.comments << "INFO: found identifier '#{@identifier}' using Schema.org distribution property.\n"
            return @identifier
          else
            meta.comments << "INFO: '#{prop}' did not result in any query match.\n"
          end

        elsif prop =~ /dcat\#/
          query = SPARQL.parse("select ?b where {
                                      ?s <#{prop}> ?o .}")
          results = query.execute(g)
          if results.any?
            unless results.first[:o].respond_to? :value
              meta.comments << "INFO: '#{prop}' data identifier did not have the expected structure.  Moving on.\n"
              next
            end
            @identifier = results.first[:b].value
            meta.comments << "INFO: found data identifier '#{@identifier}' using DCAT '#{prop}' property.\n"
            return @identifier
          else
            meta.comments << "INFO: '#{prop}' did not result in any query match.\n"
          end
        elsif prop =~ /mainEntity/
          query = SPARQL.parse("select ?o where {
                                      VALUES ?schemaidentifier {<http://schema.org/identifier> <https://schema.org/identifier>}
                                      ?s <#{prop}> ?entity .
                    ?entity  ?schemaidentifier ?o}")
          results = query.execute(g)
          if results.any?
            unless results.first[:o].respond_to? :value
              meta.comments << "INFO: '#{prop}' data identifier did not have the expected structure.  Moving on.\n"
              next
            end
            @identifier = results.first[:o].value
            meta.comments << "INFO: found identifier '#{@identifier}' using schema:mainEntity containing a schema:identifier clause.\n"
            return @identifier
          else
            meta.comments << "INFO: '#{prop}' did not result in any query match.\n"
          end

        else
          query = SPARQL.parse("select ?o where {?s <#{prop}> ?o}")
          results = query.execute(g)
          if results.any?
            unless results.first[:o].respond_to? :value
              meta.comments << "INFO: '#{prop}' data identifier did not have the expected structure.  Moving on.\n"
              next
            end
            @identifier = results.first[:o].value
            meta.comments << "INFO: found identifier '#{@identifier}' using #{prop}.\n"
            return @identifier
          else
            meta.comments << "INFO: '#{prop}' did not result in any query match.\n"
          end
        end
      end
      meta.comments << "INFO: No data identifier found in this chunk of metadata.\n"

      @identifier # returns nil if we get to this line
    end
  end
end
