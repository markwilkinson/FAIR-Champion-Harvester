# frozen_string_literal: true

RSpec.describe FAIRChampionHarvester::MetadataObject do
  describe "#merge_rdf" do
    def statements(count)
      (1..count).map do |i|
        RDF::Statement.new(RDF::URI("https://example.org/s"), RDF::URI("http://purl.org/dc/terms/title"), RDF::Literal("t#{i}"))
      end
    end

    [1, 2, 3, 4, 10].each do |count|
      it "adds every statement of a list of #{count}" do
        meta = described_class.new
        meta.merge_rdf(statements(count))
        expect(meta.graph.size).to eq(count)
      end
    end

    it "accepts a whole graph" do
      meta = described_class.new
      meta.merge_rdf(RDF::Graph.new << statements(4).first)
      expect(meta.graph.size).to eq(1)
    end
  end

  it "starts with no link hints" do
    expect(described_class.new.link_hints).to eq([])
  end
end
