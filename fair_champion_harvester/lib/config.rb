module FAIRChampionHarvester
  class Config
    config = ParseConfig.new(File.dirname(__FILE__) + "/config.conf")

    extruct_command = "extruct"
    if config["extruct"] && config["extruct"]["command"] && !config["extruct"]["command"].empty?
      extruct_command = config["extruct"]["command"]
    end
    extruct_command.strip!

    FAIRChampionHarvester::Utils::ExtructCommand = extruct_command

    rdf_command = "rdf"
    if config["rdf"] && config["rdf"]["command"] && !config["rdf"]["command"].empty?
      rdf_command = config["rdf"]["command"]
    end
    rdf_command.strip
    case rdf_command
    when /echo/i
      abort "The RDF command in the config file appears to be subject to command injection.  I will not continue"
    when !(/rdf$/ =~ $_)
      abort "this software requires that Kelloggs Distiller tool is used. The distiller command must end in 'rdf'"
    end
    FAIRChampionHarvester::Utils::RDFCommand = rdf_command

    tika_command = "http://localhost:9998/meta"
    if config["tika"] && config["tika"]["command"] && !config["tika"]["command"].empty?
      tika_command = config["tika"]["command"]
    end
    FAIRChampionHarvester::Utils::TikaCommand = tika_command
  end
end
