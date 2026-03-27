module FAIRChampionHarvester
  class Utils
    # these are all set in Config.rb
    # FAIRChampionHarvester::Utils::ExtructCommand = extruct_command
    # FAIRChampionHarvester::Utils::RDFCommand = rdf_command
    # FAIRChampionHarvester::Utils::TikaCommand = tika_command

    FAIRChampionHarvester::Utils::AcceptHeader = { "Accept" => "text/turtle, application/ld+json, application/rdf+xml, text/xhtml+xml, application/n3, application/rdf+n3, application/turtle, application/x-turtle, text/n3, text/turtle, text/rdf+n3, text/rdf+turtle, application/n-triples" }

    FAIRChampionHarvester::Utils::AcceptDefaultHeader = { "Accept" => "*/*" }

    FAIRChampionHarvester::Utils::TEXT_FORMATS = {
      "text" => ["text/plain"]
    }

    FAIRChampionHarvester::Utils::RDF_FORMATS = {
      "jsonld" => ["application/ld+json", "application/vnd.schemaorg.ld+json"], # NEW FOR DATACITE
      "turtle" => ["text/turtle", "application/n3", "application/rdf+n3",
                   "application/turtle", "application/x-turtle", "text/n3", "text/turtle",
                   "text/rdf+n3", "text/rdf+turtle"],
      # 'rdfa'    => ['text/xhtml+xml', 'application/xhtml+xml'],
      "rdfxml" => ["application/rdf+xml"],
      "triples" => ["application/n-triples", "application/n-quads", "application/trig"]
    }

    FAIRChampionHarvester::Utils::XML_FORMATS = {
      "xml" => ["text/xhtml", "text/xml"]
    }

    FAIRChampionHarvester::Utils::HTML_FORMATS = {
      "html" => ["text/html", "text/xhtml+xml", "application/xhtml+xml"]
    }

    FAIRChampionHarvester::Utils::JSON_FORMATS = {
      "json" => ["application/json"]
    }

    FAIRChampionHarvester::Utils::DATA_PREDICATES = [
      "http://www.w3.org/ns/ldp#contains",
      "http://xmlns.com/foaf/0.1/primaryTopic",
      "http://purl.obolibrary.org/obo/IAO_0000136", # is about
      "http://purl.obolibrary.org/obo/IAO:0000136", # is about (not the valid URL...)
      "https://www.w3.org/ns/ldp#contains",
      "https://xmlns.com/foaf/0.1/primaryTopic",

      # 'http://schema.org/about', # removed for being too general
      "http://schema.org/mainEntity",
      "http://schema.org/codeRepository",
      "http://schema.org/distribution",
      "http://schema.org/contentUrl",
      # 'https://schema.org/about', #removed for being too general
      "https://schema.org/mainEntity",
      "https://schema.org/codeRepository",
      "https://schema.org/distribution",
      "https://schema.org/contentUrl",

      "http://www.w3.org/ns/dcat#distribution",
      "https://www.w3.org/ns/dcat#distribution",
      "http://www.w3.org/ns/dcat#dataset",
      "https://www.w3.org/ns/dcat#dataset",
      "http://www.w3.org/ns/dcat#downloadURL",
      "https://www.w3.org/ns/dcat#downloadURL",
      "http://www.w3.org/ns/dcat#accessURL",
      "https://www.w3.org/ns/dcat#accessURL",

      "http://semanticscience.org/resource/SIO_000332", # is about
      "http://semanticscience.org/resource/is-about", # is about
      "https://semanticscience.org/resource/SIO_000332", # is about
      "https://semanticscience.org/resource/is-about", # is about
      "https://purl.obolibrary.org/obo/IAO_0000136" # is about
    ]

    FAIRChampionHarvester::Utils::SELF_IDENTIFIER_PREDICATES = [
      "http://purl.org/dc/elements/1.1/identifier",
      "https://purl.org/dc/elements/1.1/identifier",
      "http://purl.org/dc/terms/identifier",
      "http://schema.org/identifier",
      "https://purl.org/dc/terms/identifier",
      "https://schema.org/identifier"
    ]

    FAIRChampionHarvester::Utils::GUID_TYPES = { "inchi" => /^\w{14}-\w{10}-\w$/,
                                                 "doi" => %r{^10.\d{4,9}/[-._;()/:A-Z0-9]+$}i,
                                                 "handle1" => %r{^[^/]+/[^/]+$}i,
                                                 "handle2" => %r{^\d{4,5}/[-._;()/:A-Z0-9]+$}i, # legacy style  12345/AGB47A
                                                 "uri" => %r{^\w+:/?/?[^\s]+$},
                                                 "purl" => /purl\./,
                                                 "ark_url" => %r{
                                                        https?://                   # http:// or https://
                                                        [^\s/]+?                    # domain name (non-greedy)
                                                        /ark:                       # /ark:
                                                        (?:/)?                      # optional extra slash (ark:/...)
                                                        [0-9]+                      # NAAN (Name Assigning Authority Number)
                                                        /                           # separator
                                                        [a-z0-9~=+*@_$.\-/]+        # Name + optional Qualifier
                                                      }ix,
                                                 "ark" => %r{
                                                        \b                          # word boundary (avoids matching inside words)
                                                        ark:                        # literal "ark:"
                                                        (?:/)?                      # optional slash
                                                        [0-9]+                      # NAAN
                                                        /                           # separator
                                                        [a-z0-9~=+*@_$.\-/]+        # Name + optional Qualifier
                                                      }ix }
  end
end
