module FAIRChampionHarvester
  class MetadataObject
    attr_accessor :hash, :graph, :guidtype, :full_response, :finalURI, :comments, :link_hints

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
      @link_hints = [] # typed links seen in Link headers / HTML, see LinkHints
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
      # not `graph << triples`: RDF.rb reads an Array as a single [s, p, o] triple,
      # so a list of statements was silently collapsed (or rejected) instead of added
      triples.each { |triple| graph << triple }
      graph
    end

    def rdf
      graph
    end
  end
end
