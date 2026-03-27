module FAIRChampionHarvester
  class Cache
    ##########################################################
    ###################  CACHE FUNCTIONS #####################
    ###################  #####################################

    def self.checkRDFCache(body)
      fs = File.join("/tmp/", "*_graphbody")
      bodies = Dir.glob(fs)
      g = RDF::Graph.new
      bodies.each do |bodyfile|
        next unless File.size(bodyfile) == body.bytesize # compare body size
        next unless bodyfile.match(/(.*)_graphbody$/) # continue if there's no match

        filename = ::Regexp.last_match(1)
        warn "Regexp match for #{filename} FOUND"
        next unless File.exist?("#{filename}_graph") # @ get the associated graph file

        warn "RDF Cache File #{filename} FOUND"
        graph = Marshal.load(File.read("#{filename}_graph")) # unmarshal it
        graph.each do |statement|
          g << statement # need to do this because the unmarshalled object isn't entirely functional as an RDF::Graph object
        end
        warn "returning a graph of #{g.size}"
        break
      end
      # return an empty graph otherwise
      g
    end

    def self.writeRDFCache(reader, body)
      filename = Digest::MD5.hexdigest body
      graph = RDF::Graph.new
      reader.each_statement { |s| graph << s }
      warn "WRITING RDF TO CACHE #{filename}"
      File.binwrite("/tmp/#{filename}_graph", Marshal.dump(graph))
      File.binwrite("/tmp/#{filename}_graphbody", body)
      warn "wrote RDF filename: #{filename}"
    end

    def self.checkCache(uri, headers)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      warn "Checking Error cache for #{filename}"
      if File.exist?("/tmp/#{filename}_error")
        warn "Error file found in cache... returning"
        return ["ERROR", nil, [uri]]
      end
      if File.exist?("/tmp/#{filename}_head") and File.exist?("/tmp/#{filename}_body")
        warn "FOUND data in cache"
        head = Marshal.load(File.read("/tmp/#{filename}_head"))
        body = Marshal.load(File.read("/tmp/#{filename}_body"))
        finalURI = [uri]
        finalURI = Marshal.load(File.read("/tmp/#{filename}_uri")) if File.exist?("/tmp/#{filename}_uri")
        warn "Returning...."
        return [head, body, finalURI]
      end
      warn "Not Found in Cache"
    end

    def self.writeToCache(uri, headers, head, body, finalURI)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      warn "in writeToCache Writing to cache for #{filename}"
      headfilename = filename + "_head"
      bodyfilename = filename + "_body"
      urifilename = filename + "_uri"
      File.binwrite("/tmp/#{headfilename}", Marshal.dump(head))
      File.binwrite("/tmp/#{bodyfilename}", Marshal.dump(body))
      File.binwrite("/tmp/#{urifilename}", Marshal.dump(finalURI))
    end

    def self.writeErrorToCache(uri, headers)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      warn "in writeErrorToCache Writing error to cache for #{filename}"
      File.binwrite("/tmp/#{filename}_error", "ERROR")
    end
  end
end
