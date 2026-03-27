module FAIRChampionHarvester
  class Distiller
    @@distillerknown = {}
    def self.do_distiller(meta, body)
      bhash = Digest::SHA256.hexdigest(body)
      if @@distillerknown[bhash]
        meta.comments << "INFO: Cached data is already parsed.  Returning\n"
        return
      end
      @@distillerknown[bhash] = true

      meta.comments << "INFO: Using 'Kellog's Distiller' to try to extract metadata from return value (message body).\n"
      #         $stderr.puts "BODY: \n\n #{body}"

      file = Tempfile.new("foo", encoding: "UTF-8")
      body = body.force_encoding("UTF-8")
      body.scrub!
      body = body.gsub(%r{"@context"\s*:\s*"https?://schema.org/?"}, '"@context": "https://schema.org/docs/jsonldcontext.json"')
      file.write(body)
      file.rewind
      # `cp #{file.path} /tmp/foooo`
      meta.comments << "INFO: The message body is being examined by Distiller\n"
      #        command = "LANG=en_US.UTF-8 #{FAIRChampionHarvester::Utils::RDFCommand} serialize --input-format rdfa --output-format turtle #{file.path} 2>/dev/null"
      # command = "LANG=en_US.UTF-8 #{FAIRChampionHarvester::Utils::RDFCommand} serialize --input-format rdfa --output-format jsonld #{file.path}"
      command = "LANG=en_US.UTF-8 #{FAIRChampionHarvester::Utils::RDFCommand} serialize --input-format rdfa --output-format jsonld #{file.path}"
      #        command = "LANG=en_US.UTF-8 /home/osboxes/.rvm/rubies/ruby-2.6.3/bin/ruby /home/osboxes/.rvm/gems/ruby-2.6.3/bin/rdf serialize --output-format jsonld #{file.path}"
      warn "distiller command: #{command}"
      result, _stderr, _status = Open3.capture3(command)
      warn ""
      # warn "distiller errors: #{_stderr}"
      file.close
      file.unlink

      result = result.force_encoding("UTF-8")
      # warn "DIST RESULT: #{result}"
      if result =~ /@context/i
        meta.comments << "INFO: The Distiller found parseable data.  Parsing as RDF\n"
        Core.parse_rdf(meta, result, "application/ld+json")
      else # failure returns nil
        meta.comments << "WARN: The Distiller tool failed to find parseable data in the body, perhaps due to incorrectly formatted HTML, or simply lack of embedded metadata.\n"
      end
    end
  end
end
