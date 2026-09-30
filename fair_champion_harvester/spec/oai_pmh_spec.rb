# frozen_string_literal: true

require_relative "support_http"

RSpec.describe FAIRChampionHarvester::OAIPMH do
  let(:meta) { FAIRChampionHarvester::MetadataObject.new }
  let(:comments) { meta.comments.join }

  def hint(href, rels: ["describedby"], type: nil, profile: nil)
    { href: href, rels: rels, type: type, profile: profile, title: nil, via: "Link header" }
  end

  # ---------------------------------------------------------------------------
  # Pure unit tests — no HTTP
  # ---------------------------------------------------------------------------
  describe ".normalise_endpoint" do
    it "strips query and fragment" do
      expect(described_class.normalise_endpoint("https://r.example/oai?verb=Identify#x")).to eq("https://r.example/oai")
    end

    it "rejects non-http(s) and blank input" do
      expect(described_class.normalise_endpoint("ftp://r.example/oai")).to be_nil
      expect(described_class.normalise_endpoint("")).to be_nil
      expect(described_class.normalise_endpoint(nil)).to be_nil
      expect(described_class.normalise_endpoint("http://bad host/")).to be_nil
    end
  end

  describe ".endpoints_from_linkset (FAIRiCat)" do
    it "reads the endpoint from the anchor when service-doc points at the OAI protocol spec" do
      doc = { "linkset" => [{
        "anchor" => "https://export.arxiv.org/oai2",
        "service-doc" => [{ "href" => "https://www.openarchives.org/OAI/openarchivesprotocol.html", "type" => "text/html" }]
      }] }
      expect(described_class.endpoints_from_linkset(doc)).to eq(["https://export.arxiv.org/oai2"])
    end

    it "recognises a service-meta link to an Identify request" do
      doc = { "linkset" => [{
        "anchor" => "https://r.example/oai",
        "service-meta" => [{ "href" => "https://r.example/oai?verb=Identify", "type" => "text/xml" }]
      }] }
      expect(described_class.endpoints_from_linkset(doc)).to eq(["https://r.example/oai"])
    end

    it "recognises the OAI spec URL under service-desc and the 2.0 path" do
      doc = { "linkset" => [{
        "anchor" => "https://r.example/oai",
        "service-desc" => [{ "href" => "http://www.openarchives.org/OAI/2.0/openarchivesprotocol.htm" }]
      }] }
      expect(described_class.endpoints_from_linkset(doc)).to eq(["https://r.example/oai"])
    end

    it "ignores entries for other services (e.g. SPARQL, OpenAPI)" do
      doc = { "linkset" => [
        { "anchor" => "https://r.example/sparql", "service-doc" => [{ "href" => "https://www.w3.org/TR/sparql11-protocol/" }] },
        { "anchor" => "https://r.example/api", "service-desc" => [{ "href" => "https://r.example/openapi.json" }] }
      ] }
      expect(described_class.endpoints_from_linkset(doc)).to eq([])
    end

    it "returns several endpoints and de-duplicates" do
      spec = [{ "href" => "https://www.openarchives.org/OAI/openarchivesprotocol.html" }]
      doc = { "linkset" => [{ "anchor" => "https://a.example/oai", "service-doc" => spec },
                            { "anchor" => "https://a.example/oai", "service-doc" => spec },
                            { "anchor" => "https://b.example/oai", "service-doc" => spec }] }
      expect(described_class.endpoints_from_linkset(doc)).to eq(%w[https://a.example/oai https://b.example/oai])
    end

    it "falls back to a verb URL when the anchor is missing" do
      doc = { "linkset" => [{ "service-meta" => [{ "href" => "https://r.example/oai?verb=Identify" }] }] }
      expect(described_class.endpoints_from_linkset(doc)).to eq(["https://r.example/oai"])
    end

    it "tolerates malformed documents" do
      expect(described_class.endpoints_from_linkset([])).to eq([])
      expect(described_class.endpoints_from_linkset("linkset" => "nope")).to eq([])
      expect(described_class.endpoints_from_linkset("linkset" => [nil, 3, { "anchor" => "x" }])).to eq([])
    end
  end

  describe ".fairicat_link?" do
    it "accepts api-catalog with the linkset media type" do
      expect(described_class.fairicat_link?(hint("https://r.example/c", rels: ["api-catalog"], type: "application/linkset+json"))).to be true
    end

    it "accepts api-catalog with no type, and with type parameters" do
      expect(described_class.fairicat_link?(hint("https://r.example/c", rels: ["api-catalog"]))).to be true
      expect(described_class.fairicat_link?(hint("https://r.example/c", rels: ["api-catalog"], type: "application/linkset+json; profile=\"x\""))).to be true
    end

    it "rejects other rels and other types" do
      expect(described_class.fairicat_link?(hint("https://r.example/c", rels: ["describedby"], type: "application/linkset+json"))).to be false
      expect(described_class.fairicat_link?(hint("https://r.example/c", rels: ["api-catalog"], type: "text/html"))).to be false
    end
  end

  describe ".heuristic_endpoints" do
    def candidates_for(*hints)
      meta.link_hints = hints
      described_class.heuristic_endpoints(meta)
    end

    it "treats a link with an OAI-PMH verb query as the strongest evidence, and keeps its identifier" do
      result = candidates_for(hint("https://api.fairsharing.org/oai?verb=GetRecord&metadataPrefix=oai_dc&identifier=oai:fairsharing_record:FAIRsharing.1547"))
      expect(result).to eq([{ endpoint: "https://api.fairsharing.org/oai", identifier: "oai:fairsharing_record:FAIRsharing.1547", score: 2 }])
    end

    it "accepts conventional endpoint paths with weaker evidence" do
      %w[/oai /oai2d /oai-pmh /oai/request /oaiprovider/request].each do |path|
        result = candidates_for(hint("https://r.example#{path}", rels: ["service-meta"]))
        expect(result.map { |c| [c[:endpoint], c[:score]] }).to eq([["https://r.example#{path}", 1]])
      end
    end

    it "ranks verb links above path guesses" do
      result = candidates_for(hint("https://a.example/oai"), hint("https://b.example/pmh?verb=Identify"))
      expect(result.map { |c| c[:endpoint] }).to eq(%w[https://b.example/pmh https://a.example/oai])
    end

    it "merges several links to the same endpoint, upgrading the score and keeping the identifier" do
      result = candidates_for(hint("https://r.example/oai"), hint("https://r.example/oai?verb=GetRecord&identifier=oai:r:1"))
      expect(result).to eq([{ endpoint: "https://r.example/oai", identifier: "oai:r:1", score: 2 }])
    end

    it "ignores unrelated links and look-alikes" do
      result = candidates_for(hint("https://r.example/about"), hint("https://r.example/oaifoo"),
                              hint("https://r.example/cite?verb=Reply"), hint("https://r.example/record/oai-notes.html"))
      expect(result).to eq([])
    end

    it "caps the number of candidates" do
      hints = (1..10).map { |i| hint("https://h#{i}.example/oai") }
      expect(candidates_for(*hints).size).to eq(described_class::MAX_CANDIDATES)
    end
  end

  describe ".entry_urls" do
    it "uses final URIs and a URL guid, and drops resolvers" do
      meta.finalURI = ["https://doi.org/10.1/x", "https://repo.example.org/record/1"]
      expect(described_class.entry_urls("https://doi.org/10.1/x", meta)).to eq(["https://repo.example.org/record/1"])
    end

    it "ignores non-URL entries such as a bare DOI" do
      expect(described_class.entry_urls("10.1/x", meta)).to eq([])
    end
  end

  describe ".identifier_candidates" do
    let(:identify) do
      Nokogiri::XML(HttpSpecSupport.instance_method(:identify_xml).bind_call(Object.new.extend(HttpSpecSupport))).tap(&:remove_namespaces!)
    end

    it "builds identifiers from the sample identifier's scheme, trying the URL tail and the DOI" do
      ids = described_class.identifier_candidates(identify, "10.5281/zenodo.12345", ["https://repo.example.org/records/12345"])
      expect(ids.first(3)).to eq(%w[oai:repo.example.org:12345 oai:repo.example.org:10.5281/zenodo.12345 oai:repo.example.org:zenodo.12345])
    end

    it "finishes with the GUID and URLs themselves, for repositories that use URLs as identifiers" do
      ids = described_class.identifier_candidates(identify, "https://repo.example.org/r/1", ["https://repo.example.org/r/1"])
      expect(ids.last).to eq("https://repo.example.org/r/1")
    end

    it "falls back to the repositoryIdentifier when there is no sample" do
      xml = Nokogiri::XML(%(<OAI-PMH><Identify><description><oai-identifier><repositoryIdentifier>x.org</repositoryIdentifier></oai-identifier></description></Identify></OAI-PMH>))
      ids = described_class.identifier_candidates(xml, "g", ["https://x.org/rec/7"])
      expect(ids.first).to eq("oai:x.org:7")
    end

    it "offers only the raw GUID and URLs when the server has no oai-identifier description" do
      xml = Nokogiri::XML("<OAI-PMH><Identify/></OAI-PMH>")
      expect(described_class.identifier_candidates(xml, "https://x.org/rec/7", ["https://x.org/rec/7"]))
        .to eq(["https://x.org/rec/7"])
    end
  end

  describe ".dc_triples" do
    let(:dc) do
      Nokogiri::XML(<<~XML).at_xpath("/*")
        <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>T</dc:title><dc:identifier>https://doi.org/10.1/x</dc:identifier><dc:description>   </dc:description>
        </oai_dc:dc>
      XML
    end

    it "emits DC element statements about the subject, skipping empty values, with identifiers as IRIs" do
      triples = described_class.dc_triples(dc, "https://r.example/rec/1")
      expect(triples.size).to eq(2)
      expect(triples).to include(RDF::Statement.new(RDF::URI("https://r.example/rec/1"), RDF::URI("http://purl.org/dc/elements/1.1/title"), RDF::Literal("T")))
      expect(triples).to include(RDF::Statement.new(RDF::URI("https://r.example/rec/1"), RDF::URI("http://purl.org/dc/elements/1.1/identifier"), RDF::URI("https://doi.org/10.1/x")))
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end with stubbed HTTP
  # ---------------------------------------------------------------------------
  context "with stubbed HTTP" do
    include_context "with stubbed HTTP"

    let(:landing) { "https://repo.example.org/records/12345" }
    let(:endpoint) { "https://repo.example.org/oai" }
    let(:oai_id) { "oai:repo.example.org:12345" }

    before do
      meta.finalURI = [landing]
      stub_request(:get, %r{/\.well-known/api-catalog}).to_return(status: 404)
    end

    def oai(verb, extra = {})
      stub_request(:get, endpoint).with(query: { "verb" => verb }.merge(extra))
    end

    def stub_working_server
      oai("Identify").to_return(body: identify_xml)
      oai("ListMetadataFormats").to_return(body: list_formats_xml("oai_dc"))
      oai("GetRecord", "identifier" => oai_id, "metadataPrefix" => "oai_dc").to_return(body: get_record_xml(oai_id))
    end

    def fairicat_body(anchor = endpoint)
      JSON.generate("linkset" => [{ "anchor" => anchor,
                                    "service-doc" => [{ "href" => "https://www.openarchives.org/OAI/openarchivesprotocol.html", "type" => "text/html" }] }])
    end

    context "when the publisher declares the endpoint with FAIRiCat" do
      before { stub_working_server }

      it "follows a Link header api-catalog, verifies the endpoint and harvests the record" do
        meta.link_hints = [hint("https://repo.example.org/fairicat/api-info.json", rels: ["api-catalog"], type: "application/linkset+json")]
        stub_request(:get, "https://repo.example.org/fairicat/api-info.json").to_return(body: fairicat_body)

        described_class.resolve_oaipmh(landing, meta)

        expect(comments).to include("Reading FAIRiCat catalog https://repo.example.org/fairicat/api-info.json")
        expect(comments).to include("valid OAI-PMH server (found via FAIRiCat)")
        expect(comments).to include("Found OAI-PMH record #{oai_id}")
        titles = meta.graph.query([RDF::URI(landing), RDF::URI("http://purl.org/dc/elements/1.1/title"), nil]).map { |s| s.object.to_s }
        expect(titles).to eq(["A Test Dataset"])
      end

      it "falls back to /.well-known/api-catalog" do
        stub_request(:get, "https://repo.example.org/.well-known/api-catalog").to_return(body: fairicat_body)
        described_class.resolve_oaipmh(landing, meta)
        expect(comments).to include("found via FAIRiCat")
        expect(meta.graph.size).to be > 0
      end

      it "prefers FAIRiCat to heuristics: a misleading /oai link is never contacted" do
        meta.link_hints = [hint("https://decoy.example/oai?verb=Identify")]
        stub_request(:get, "https://repo.example.org/.well-known/api-catalog").to_return(body: fairicat_body)
        described_class.resolve_oaipmh(landing, meta)
        expect(a_request(:any, %r{decoy\.example})).not_to have_been_made
      end

      it "tries the next catalog candidate when the first declares nothing useful" do
        meta.link_hints = [hint("https://repo.example.org/empty.json", rels: ["api-catalog"], type: "application/linkset+json")]
        stub_request(:get, "https://repo.example.org/empty.json").to_return(body: JSON.generate("linkset" => []))
        stub_request(:get, "https://repo.example.org/.well-known/api-catalog").to_return(body: fairicat_body)
        described_class.resolve_oaipmh(landing, meta)
        expect(comments).to include("found via FAIRiCat")
      end

      it "survives a catalog that is not JSON and then uses heuristics" do
        meta.link_hints = [hint("https://repo.example.org/bad", rels: ["api-catalog"]), hint("#{endpoint}?verb=Identify")]
        stub_request(:get, "https://repo.example.org/bad").to_return(body: "<html>oops")
        described_class.resolve_oaipmh(landing, meta)
        expect(comments).to include("is not valid JSON")
        expect(comments).to include("found via heuristic guess")
      end

      it "does not trust a declared endpoint that fails the Identify check" do
        stub_request(:get, "https://repo.example.org/.well-known/api-catalog").to_return(body: fairicat_body("https://repo.example.org/not-oai"))
        stub_request(:get, "https://repo.example.org/not-oai").with(query: { "verb" => "Identify" }).to_return(body: "<html>hello</html>")
        described_class.resolve_oaipmh(landing, meta)
        expect(comments).to include("did not answer as an OAI-PMH server")
        expect(meta.graph).to be_empty
      end
    end

    context "when there is no FAIRiCat and we have to guess" do
      it "finds the endpoint from a Link header verb URL and uses the identifier it carries" do
        meta.link_hints = [hint("#{endpoint}?verb=GetRecord&metadataPrefix=oai_dc&identifier=oai:weird:scheme/77")]
        oai("Identify").to_return(body: identify_xml)
        oai("ListMetadataFormats").to_return(body: list_formats_xml("oai_dc"))
        oai("GetRecord", "identifier" => "oai:weird:scheme/77", "metadataPrefix" => "oai_dc").to_return(body: get_record_xml("oai:weird:scheme/77"))

        described_class.resolve_oaipmh(landing, meta)

        expect(comments).to include("found via heuristic guess")
        expect(comments).to include("Found OAI-PMH record oai:weird:scheme/77")
        expect(meta.graph.size).to be > 0
      end

      it "finds the endpoint from a conventional path and derives the identifier" do
        meta.link_hints = [hint(endpoint, rels: ["service-meta"])]
        stub_working_server
        described_class.resolve_oaipmh(landing, meta)
        expect(comments).to include("Found OAI-PMH record #{oai_id}")
      end

      it "rejects a guessed endpoint that does not speak OAI-PMH, without harvesting" do
        meta.link_hints = [hint(endpoint)]
        oai("Identify").to_return(body: "<html><body>Not here</body></html>")
        described_class.resolve_oaipmh(landing, meta)
        expect(comments).to include("did not answer as an OAI-PMH server")
        expect(comments).to include("No OAI-PMH endpoint could be identified")
        expect(meta.graph).to be_empty
      end

      it "rejects a guessed endpoint that returns malformed XML or an HTTP error" do
        meta.link_hints = [hint(endpoint), hint("https://other.example/oai")]
        oai("Identify").to_return(body: "<OAI-PMH><unclosed>")
        stub_request(:get, "https://other.example/oai").with(query: { "verb" => "Identify" }).to_return(status: 500)
        expect { described_class.resolve_oaipmh(landing, meta) }.not_to raise_error
        expect(comments).to include("No OAI-PMH endpoint could be identified")
      end
    end

    context "when nothing suggests an OAI-PMH server" do
      it "makes no OAI-PMH requests, only the well-known probe, and adds no WARN comments" do
        meta.link_hints = [hint("https://repo.example.org/about")]
        described_class.resolve_oaipmh(landing, meta)
        expect(a_request(:any, /verb=/)).not_to have_been_made
        expect(a_request(:get, "https://repo.example.org/.well-known/api-catalog")).to have_been_made.once
        expect(comments).not_to include("WARN")
        expect(meta.graph).to be_empty
      end

      it "does nothing for a resource that never resolved to a URL" do
        meta.finalURI = []
        described_class.resolve_oaipmh("10.1234/abc", meta)
        expect(a_request(:any, /.*/)).not_to have_been_made
        expect(meta.comments).to be_empty
      end

      it "never looks for a catalog on a resolver such as doi.org" do
        meta.finalURI = ["https://doi.org/10.1/x"]
        described_class.resolve_oaipmh("https://doi.org/10.1/x", meta)
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end

    context "when the server is valid but the record cannot be located" do
      it "says so, and suggests publishing the identifier, without failing" do
        meta.link_hints = [hint(endpoint)]
        oai("Identify").to_return(body: identify_xml)
        oai("ListMetadataFormats").to_return(body: list_formats_xml("oai_dc"))
        stub_request(:get, endpoint).with(query: hash_including("verb" => "GetRecord")).to_return(body: oai_error_xml("idDoesNotExist"))

        described_class.resolve_oaipmh(landing, meta)

        expect(comments).to include("none of the identifiers that can be derived")
        expect(comments).not_to include("WARN")
        expect(a_request(:get, endpoint).with(query: hash_including("verb" => "GetRecord"))).to have_been_made.at_most_times(described_class::MAX_IDENTIFIER_ATTEMPTS)
      end

      it "keeps trying candidates until one matches" do
        meta.link_hints = [hint(endpoint)]
        oai("Identify").to_return(body: identify_xml)
        oai("ListMetadataFormats").to_return(body: list_formats_xml("oai_dc"))
        stub_request(:get, endpoint).with(query: hash_including("verb" => "GetRecord")).to_return(body: oai_error_xml("idDoesNotExist"))
        oai("GetRecord", "identifier" => landing, "metadataPrefix" => "oai_dc").to_return(body: get_record_xml(landing))
        described_class.resolve_oaipmh(landing, meta)
        expect(comments).to include("Found OAI-PMH record #{landing}")
      end
    end

    context "when the server offers a richer metadata format" do
      it "also harvests the preferred format into the metadata hash" do
        meta.link_hints = [hint(endpoint)]
        oai("Identify").to_return(body: identify_xml)
        oai("ListMetadataFormats").to_return(body: list_formats_xml("oai_dc", "oai_datacite"))
        oai("GetRecord", "identifier" => oai_id, "metadataPrefix" => "oai_dc").to_return(body: get_record_xml(oai_id))
        datacite = oai_envelope(<<~XML, verb: "GetRecord")
          <GetRecord><record><header><identifier>#{oai_id}</identifier></header>
          <metadata><resource xmlns="http://datacite.org/schema/kernel-4"><titles><title>DC4 title</title></titles></resource></metadata>
          </record></GetRecord>
        XML
        oai("GetRecord", "identifier" => oai_id, "metadataPrefix" => "oai_datacite").to_return(body: datacite)

        described_class.resolve_oaipmh(landing, meta)

        expect(comments).to include("Also harvesting the 'oai_datacite' metadata format")
        expect(meta.hash.to_s).to include("DC4 title")
      end
    end

    context "when unexpected errors occur" do
      it "never propagates them into the harvest" do
        meta.link_hints = [hint(endpoint)]
        allow(described_class).to receive(:heuristic_endpoints).and_raise(RuntimeError, "boom")
        expect { described_class.resolve_oaipmh(landing, meta) }.not_to raise_error
        expect(comments).to include("WARN: OAI-PMH harvesting stopped after an unexpected error (RuntimeError: boom)")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Wiring
  # ---------------------------------------------------------------------------
  describe "integration with Core.resolveit" do
    it "is invoked for resolvable GUIDs" do
      allow(FAIRChampionHarvester::Uri).to receive(:resolve_uri) { |_g, m| m.comments << "INFO: stub\n" }
      expect(described_class).to receive(:resolve_oaipmh).with("https://repo.example.org/x", kind_of(FAIRChampionHarvester::MetadataObject))
      FAIRChampionHarvester::Core.resolveit("https://repo.example.org/x")
    end

    it "is skipped for unknown GUID types" do
      expect(described_class).not_to receive(:resolve_oaipmh)
      FAIRChampionHarvester::Core.resolveit("not a guid")
    end
  end
end

RSpec.describe "OAI-PMH hint capture in URL.resolve_url" do
  include_context "with stubbed HTTP"

  it "records Link header and HTML link hints of every rel" do
    meta = FAIRChampionHarvester::MetadataObject.new
    stub_request(:get, "https://repo.example.org/rec").to_return(
      headers: { "Content-Type" => "text/html", "Link" => '<https://repo.example.org/cat>; rel="api-catalog"; type="application/linkset+json"' },
      body: '<html><head><link rel="service-meta" href="/oai?verb=Identify"></head></html>'
    )
    allow(FAIRChampionHarvester::Extruct).to receive(:do_extruct)
    allow(FAIRChampionHarvester::Distiller).to receive(:do_distiller)

    FAIRChampionHarvester::URL.resolve_url(guid: "https://repo.example.org/rec", meta: meta, nolinkheaders: true)

    expect(meta.link_hints.map { |h| [h[:via], h[:rels]] }).to include(["Link header", ["api-catalog"]], ["HTML link", ["service-meta"]])
    expect(meta.link_hints.map { |h| h[:href] }).to include("https://repo.example.org/oai?verb=Identify")
  end
end
