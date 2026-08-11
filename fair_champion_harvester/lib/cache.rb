module FAIRChampionHarvester
  class Cache
    ##########################################################
    ###################  CACHE FUNCTIONS #####################
    ###################  #####################################

    # Cache time-to-live in seconds. Configurable via the +CACHE_TTL+ env
    # var; defaults to 5 minutes (short by design, unlike FDP-Index-Proxy's
    # 24h FDP_CACHE_TTL, since harvested DCAT/TTL records under test change
    # frequently and testers need to see edits reflected quickly).
    CACHE_TTL = (ENV.fetch("CACHE_TTL", 300)).to_i

    def self.expired?(timestamp_file)
      return true unless File.exist?(timestamp_file)

      age = Time.now - Marshal.load(File.read(timestamp_file))
      age > CACHE_TTL
    end

    def self.checkRDFCache(body)
      g = RDF::Graph.new
      key = Digest::MD5.hexdigest body
      graph_file = "/tmp/#{key}_graph"
      body_file  = "/tmp/#{key}_graphbody"
      time_file  = "/tmp/#{key}_graphtime"

      return g unless File.exist?(graph_file) && File.exist?(body_file)

      if expired?(time_file)
        warn "RDF Cache File #{key} EXPIRED"
        purgeRDFFiles(key)
        return g
      end

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
      File.binwrite("/tmp/#{filename}_graphtime", Marshal.dump(Time.now))
      warn "wrote RDF filename: #{filename}"
    end

    def self.checkCache(uri, headers)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      time_file = "/tmp/#{filename}_time"
      warn "Checking Error cache for #{filename}"

      if File.exist?("/tmp/#{filename}_error")
        if expired?(time_file)
          warn "Error cache file #{filename} EXPIRED"
          purgeFiles(filename)
        else
          warn "Error file found in cache... returning"
          return ["ERROR", nil, [uri]]
        end
      end

      if File.exist?("/tmp/#{filename}_head") and File.exist?("/tmp/#{filename}_body")
        if expired?(time_file)
          warn "Cache #{filename} EXPIRED"
          purgeFiles(filename)
          warn "Not Found in Cache"
          return
        end

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
      timefilename = filename + "_time"
      File.binwrite("/tmp/#{headfilename}", Marshal.dump(head))
      File.binwrite("/tmp/#{bodyfilename}", Marshal.dump(body))
      File.binwrite("/tmp/#{urifilename}", Marshal.dump(finalURI))
      File.binwrite("/tmp/#{timefilename}", Marshal.dump(Time.now))
    end

    def self.writeErrorToCache(uri, headers)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      warn "in writeErrorToCache Writing error to cache for #{filename}"
      File.binwrite("/tmp/#{filename}_error", "ERROR")
      File.binwrite("/tmp/#{filename}_time", Marshal.dump(Time.now))
    end

    # Force-evicts the cache entry (data and/or error) for a given uri+headers,
    # regardless of TTL. Use this to bypass a stale or bad cached result
    # without waiting for CACHE_TTL to elapse or restarting the container.
    def self.purge(uri, headers)
      filename = Digest::MD5.hexdigest uri + headers.to_s
      purgeFiles(filename)
    end

    def self.purgeFiles(filename)
      %w[_head _body _uri _error _time].each do |suffix|
        path = "/tmp/#{filename}#{suffix}"
        File.delete(path) if File.exist?(path)
      end
    end
    private_class_method :purgeFiles

    def self.purgeRDFFiles(key)
      %w[_graph _graphbody _graphtime].each do |suffix|
        path = "/tmp/#{key}#{suffix}"
        File.delete(path) if File.exist?(path)
      end
    end
    private_class_method :purgeRDFFiles
  end
end
