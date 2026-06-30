# frozen_string_literal: true

RSpec.describe FAIRChampionHarvester do
  it "has a version number" do
    expect(FairChampionHarvester::VERSION).not_to be_nil
  end

  # ---------------------------------------------------------------------------
  # Unit tests — no network required
  # ---------------------------------------------------------------------------
  describe FAIRChampionHarvester::Core do
    describe ".parse_link_http_headers" do
      def hdr(link_value)
        { link: link_value }
      end

      it "returns [] when link header is absent" do
        expect(described_class.parse_link_http_headers({})).to eq([])
      end

      it "returns [] when link header is nil" do
        expect(described_class.parse_link_http_headers(hdr(nil))).to eq([])
      end

      context "with a single String (traditional comma-separated header)" do
        it "extracts an 'alternate' URL" do
          result = described_class.parse_link_http_headers(hdr('<https://example.org/meta>; rel="alternate"'))
          expect(result).to eq(["https://example.org/meta"])
        end

        it "extracts a 'describedby' URL" do
          result = described_class.parse_link_http_headers(hdr('<https://example.org/desc>; rel="describedby"'))
          expect(result).to eq(["https://example.org/desc"])
        end

        it "extracts a 'meta' URL" do
          result = described_class.parse_link_http_headers(hdr('<https://example.org/meta>; rel="meta"'))
          expect(result).to eq(["https://example.org/meta"])
        end

        it "ignores unrecognised rel types (e.g. 'cite-as')" do
          result = described_class.parse_link_http_headers(hdr('<https://example.org/cite>; rel="cite-as"'))
          expect(result).to be_empty
        end

        it "handles multiple comma-separated entries in one string" do
          result = described_class.parse_link_http_headers(
            hdr('<https://example.org/a>; rel="alternate", <https://example.org/b>; rel="describedby"')
          )
          expect(result).to contain_exactly("https://example.org/a", "https://example.org/b")
        end

        it "correctly parses hyphenated rel types (regex fix: \\w+ → [\\w-]+)" do
          # 'cite-as' was previously mis-parsed as 'cite', passing the allowlist check by accident.
          # Now the full token is captured and correctly filtered out.
          result = described_class.parse_link_http_headers(
            hdr('<https://example.org/cite>; rel="cite-as", <https://example.org/desc>; rel="describedby"')
          )
          expect(result).to eq(["https://example.org/desc"])
        end

        it "skips entries with no angle-bracket URL" do
          result = described_class.parse_link_http_headers(hdr('no-url-here; rel="alternate"'))
          expect(result).to be_empty
        end
      end

      context "with an Array (one element per Link: header line)" do
        it "extracts URLs from all headers" do
          result = described_class.parse_link_http_headers(hdr([
            '<https://example.org/a>; rel="alternate"',
            '<https://example.org/b>; rel="describedby"'
          ]))
          expect(result).to contain_exactly("https://example.org/a", "https://example.org/b")
        end

        it "handles comma-separated entries within individual array elements" do
          result = described_class.parse_link_http_headers(hdr([
            '<https://example.org/a>; rel="alternate", <https://example.org/b>; rel="meta"',
            '<https://example.org/c>; rel="describedby"'
          ]))
          expect(result).to contain_exactly(
            "https://example.org/a",
            "https://example.org/b",
            "https://example.org/c"
          )
        end
      end

      context "with FairSharing-style multi-header response" do
        let(:fairsharing_headers) do
          hdr([
            '<https://fairsharing.org/1547>; rel="cite-as"',
            '<https://fairsharing.org/1547>; rel="describedby"; type="application/ld+json"',
            '<https://fairsharing.org/1547>; rel="describedby"; type="application/json"',
            '<https://api.fairsharing.org/oai?verb=GetRecord&metadataPrefix=oai_dc&identifier=oai:fairsharing_record:FAIRsharing.1547>; rel="describedby"; type="text/xml"'
          ])
        end

        it "returns describedby URLs and ignores cite-as" do
          result = described_class.parse_link_http_headers(fairsharing_headers)
          expect(result).to include("https://fairsharing.org/1547")
          expect(result).to include(
            "https://api.fairsharing.org/oai?verb=GetRecord&metadataPrefix=oai_dc&identifier=oai:fairsharing_record:FAIRsharing.1547"
          )
        end

        it "does not include the cite-as URL as a separate entry" do
          result = described_class.parse_link_http_headers(fairsharing_headers)
          # 'cite-as' is not in the allowlist; the fairsharing.org URL should only appear
          # via the describedby entries, not an extra time from cite-as
          expect(result.count("https://fairsharing.org/1547")).to eq(2) # once per describedby
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests — JSON-LD context expansion (no network required)
  # ---------------------------------------------------------------------------
  describe FAIRChampionHarvester::Core do
    describe ".parse_rdf" do
      let(:meta) { FAIRChampionHarvester::MetadataObject.new }

      before do
        # Clear RDF graph cache so previous runs don't produce false cache hits
        Dir.glob("/tmp/*_graph").each { |f| File.delete(f) }
        Dir.glob("/tmp/*_graphbody").each { |f| File.delete(f) }
      end

      context "with JSON-LD using a remote schema.org @context" do
        # schema.org license property has "@type": "@id", so the URL must be coerced to an IRI
        # resource rather than left as a string literal. This requires context expansion.
        let(:jsonld_body) do
          JSON.generate(
            "@context" => "http://schema.org",
            "@id" => "https://example.com/dataset/jsonld-license-test",
            "license" => "https://creativecommons.org/licenses/by/4.0/legalcode"
          )
        end

        before { described_class.parse_rdf(meta, jsonld_body, "application/ld+json") }

        it "parses license as an IRI resource (RDF::URI), not a string literal" do
          triples = meta.graph.query([nil, RDF::URI("http://schema.org/license"), nil]).to_a
          expect(triples).not_to be_empty
          obj = triples.first.object
          expect(obj).to be_a(RDF::URI), "Expected RDF::URI but got #{obj.class}: #{obj.inspect}"
          expect(obj.to_s).to eq("https://creativecommons.org/licenses/by/4.0/legalcode")
        end

        it "reports successful context expansion in comments" do
          expect(meta.comments).to include("INFO: JSON-LD context resolved and expanded successfully.\n")
        end
      end

      context "with JSON-LD as a top-level array (wrapped document)" do
        # extruct and some APIs return JSON-LD as a JSON array rather than a bare object;
        # JSON.parse returns an Array and indexing it with a String key raises TypeError
        # unless the array case is handled before the @context debug lookup.
        let(:jsonld_body) do
          JSON.generate([{
            "@context" => "http://schema.org",
            "@id" => "https://example.com/dataset/array-wrapped-test",
            "name" => "Array-wrapped Test Dataset"
          }])
        end

        it "handles array-wrapped JSON-LD without raising" do
          expect { described_class.parse_rdf(meta, jsonld_body, "application/ld+json") }.not_to raise_error
        end

        it "still extracts triples from array-wrapped JSON-LD" do
          described_class.parse_rdf(meta, jsonld_body, "application/ld+json")
          triples = meta.graph.query([nil, RDF::URI("http://schema.org/name"), nil]).to_a
          expect(triples).not_to be_empty
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests — live network calls
  # ---------------------------------------------------------------------------
  describe "live resolution", :live do
    before(:context) do
      # Clear stale error cache files so previous failures don't poison this run
      Dir.glob("/tmp/*_error").each { |f| File.delete(f) }
    end

    subject(:meta) { FAIRChampionHarvester::Core.resolveit("https://fairsharing.org/1547") }

    it "returns a MetadataObject" do
      expect(meta).to be_a(FAIRChampionHarvester::MetadataObject)
    end

    it "identifies the GUID as a URI" do
      expect(meta.guidtype).to eq("uri")
    end

    it "does not raise an undefined `url` variable error" do
      bad = meta.comments.select { |c| c.include?("undefined local variable or method") }
      expect(bad).to be_empty, "Got unexpected NameError(s):\n#{bad.join}"
    end

    it "follows at least one describedby Link header" do
      followed = meta.comments.select { |c| c.include?("being followed") }
      expect(followed).not_to be_empty
    end

    it "accumulates response bodies" do
      expect(meta.full_response).not_to be_empty
    end

    it "records a final resolved URI" do
      expect(meta.finalURI).not_to be_empty
    end
  end
end
