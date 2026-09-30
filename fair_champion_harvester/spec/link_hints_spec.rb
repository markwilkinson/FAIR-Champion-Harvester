# frozen_string_literal: true

RSpec.describe FAIRChampionHarvester::LinkHints do
  let(:base) { "https://repo.example.org/record/1" }

  describe ".from_headers" do
    it "returns [] without headers" do
      expect(described_class.from_headers(nil, base)).to eq([])
    end

    it "parses href, rels, type and profile" do
      headers = { link: '<https://repo.example.org/cat>; rel="api-catalog"; type="application/linkset+json"; profile="https://signposting.org/FAIRiCat/"' }
      hint = described_class.from_headers(headers, base).first
      expect(hint).to include(href: "https://repo.example.org/cat", rels: ["api-catalog"],
                              type: "application/linkset+json", profile: "https://signposting.org/FAIRiCat/",
                              via: "Link header")
    end

    it "keeps links of every rel, not just metadata rels" do
      headers = { link: '<https://a.example/x>; rel="cite-as", <https://a.example/y>; rel="license"' }
      expect(described_class.from_headers(headers, base).map { |h| h[:rels] }).to eq([["cite-as"], ["license"]])
    end

    it "splits space-separated rel tokens" do
      hint = described_class.from_headers({ link: '<https://a.example/x>; rel="alternate describedby"' }, base).first
      expect(hint[:rels]).to eq(%w[alternate describedby])
    end

    it "handles an Array of header lines" do
      headers = { link: ['<https://a.example/1>; rel="item"', '<https://a.example/2>; rel="item"'] }
      expect(described_class.from_headers(headers, base).map { |h| h[:href] }).to eq(%w[https://a.example/1 https://a.example/2])
    end

    it "does not split on a comma inside the URL" do
      headers = { link: '<https://a.example/oai?verb=GetRecord&identifier=oai:x:1,2>; rel="describedby"' }
      expect(described_class.from_headers(headers, base).map { |h| h[:href] })
        .to eq(["https://a.example/oai?verb=GetRecord&identifier=oai:x:1,2"])
    end

    it "resolves relative hrefs against the base" do
      hint = described_class.from_headers({ link: '</oai>; rel="service-meta"' }, base).first
      expect(hint[:href]).to eq("https://repo.example.org/oai")
    end

    it "ignores entries without rel and non-http(s) hrefs" do
      headers = { link: '<https://a.example/x>; type="text/html", <mailto:a@b.c>; rel="author"' }
      expect(described_class.from_headers(headers, base)).to eq([])
    end

    it "works with a real HTTP::Headers object" do
      headers = HTTP::Headers.coerce("Link" => ['<https://a.example/1>; rel="item"', '<https://a.example/2>; rel="item"'])
      expect(described_class.from_headers(headers, base).size).to eq(2)
    end
  end

  describe ".from_html" do
    let(:html) do
      <<~HTML
        <html><head>
          <link rel="alternate" type="application/rdf+xml" href="/meta.rdf">
          <link rel="search" type="application/opensearchdescription+xml" href="https://other.example/os.xml">
          <link rel="stylesheet" href="style.css">
          <link href="no-rel.css">
        </head><body></body></html>
      HTML
    end

    it "extracts <link> elements that have rel and href, made absolute" do
      hints = described_class.from_html(html, base)
      expect(hints.map { |h| h[:href] }).to eq(%w[https://repo.example.org/meta.rdf https://other.example/os.xml
                                                  https://repo.example.org/record/style.css])
      expect(hints.first).to include(rels: ["alternate"], type: "application/rdf+xml", via: "HTML link")
    end

    it "skips non-HTML content types" do
      expect(described_class.from_html(html, base, content_type: "application/pdf")).to eq([])
    end

    it "returns [] for an empty body" do
      expect(described_class.from_html("", base)).to eq([])
      expect(described_class.from_html(nil, base)).to eq([])
    end
  end
end
