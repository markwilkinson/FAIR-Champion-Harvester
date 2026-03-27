module FAIRChampionHarvester
  class FAIRsharing
    attr_accessor :fairsharing_key_location

    def initialize(fairsharing_key_location: "")
      @fairsharing_key_location = fairsharing_key_location
    end

    def fairsharing_key
      @fairsharing_key_location
    end
  end
end
