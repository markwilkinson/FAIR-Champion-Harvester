module FAIRChampionHarvester
  class MetadataObject
    attr_accessor :hash, :graph, :guidtype, :full_response, :finalURI, :comments

    # a hash of metadata
    # a RDF.rb graph of metadata
    # an array of comments
    # the type of GUID that was detected # will be an array of Net::HTTP::Response

    def initialize
      @hash = {}
      @graph = RDF::Graph.new
      @full_response = []
      @finalURI = []
      @comments = []
    end

    class << self
      attr_reader :comments
    end

    def self.clear_comments
      @comments = []
    end

    def merge_hash(hash)
      # $stderr.puts "\n\n\nIncoming Hash #{hash.inspect}"
      self.hash = self.hash.merge(hash)
    end

    def merge_rdf(triples) # incoming list of triples
      graph << triples
      graph
    end

    def rdf
      graph
    end
  end
end
