module FAIRChampionHarvester
  class Tika
    def self.do_tika(meta, body)
      file = Tempfile.new("foo")
      file.binmode
      file.write(body)
      file.rewind
      meta.comments << "INFO: The message body is being examined by Apache Tika\n"

      result = `curl --silent -T #{file.path} #{FAIRChampionHarvester::Utils::TikaCommand} --header "Accept: application/rdf+xml" 2>&1`
      file.close
      file.unlink # deletes the temp file
      meta.comments << "INFO: The response from Apache Tika is being parsed\n"

      FAIRChampionHarvester::Tika.parse_tika_output(meta, result)
    end

    def self.parse_tika_output(meta, output)
      # $stderr.puts "\n\n\n\n\nTIKA OUTPUT\n\nX#{output}X\n\n\n\n\n"
      # annoyingly, when you ask Tika for rdfxml, it gives it to you INSIDE an XML element
      # meaning that you cannot directly parse it as RDF.   Grrrrrrr....
      meta.comments << "INFO:  entering Tika parser - sample of input #{output[0..50]}.\n"

      unless output[0] == "<" # check if it is XML
        meta.comments << "CRITICAL:  Tika parser expected XML. Aborting. \n"
        return
      end

      xml = Nokogiri::XML(output)
      rdf = xml.xpath("//rdf:RDF", "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#")
      rdf_string = rdf.to_xml

      r = RDF::Format.for(content_type: "application/rdf+xml").reader.new(rdf_string)
      g = RDF::Graph.new << r
      meta.merge_rdf(g.statements)
      meta.comments << "INFO: Tika executed successfully (this doesn't necessarily mean that it discovered any metadata...)\n"
    end
  end
end
