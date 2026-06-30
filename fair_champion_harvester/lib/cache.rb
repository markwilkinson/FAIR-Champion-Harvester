module FAIRChampionHarvester
  class Cache
    ##########################################################
    ###################  CACHE FUNCTIONS #####################
    ###################  #####################################

    def self.checkRDFCache(body)
      g = RDF::Graph.new
      key = Digest::MD5.hexdigest body
      graph_file = "/tmp/#{key}_graph"
      body_file  = "/tmp/#{key}_graphbody"

      return g unless File.exist?(graph_file) && File.exist?(body_file)

      warn "RDF Cache File #{key} FOUND"
      graph = Marshal.load(File.read(graph_file))
      graph.each { |statement| g << statement }
      warn "returning a graph of #{g.size}"
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
