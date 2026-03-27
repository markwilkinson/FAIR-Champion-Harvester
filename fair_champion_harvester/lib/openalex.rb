module FAIRChampionHarvester
  class OpenAlex
    def self.openalex_doi(guid, meta)
      guid.downcase!
      type, url = convertToOpenAlex(guid) # returns doi, http://lopenalex...

      meta.guidtype = type if meta.guidtype.nil?
      unless type
        meta.comments << "WARN:  Was not given a DOI.  I am going to fail\n"
        return meta
      end
      meta.comments << "INFO:  Found a DOI.\n"

      FAIRChampionHarvester::URL.resolve_url(guid: url, meta: meta, nolinkheaders: true) # the true is to prevent recursive pursuit of link headers
      meta.comments << "INFO: parsing of OpenAlex #{url} complete.\n"

      meta
    end

    def self.convertToOpenAlex(guid)
      guid = guid.sub(%r{^https?://[\w.]+/}, "")
      guid = guid.sub(/^doi:/, "")
      FAIRChampionHarvester::Utils::GUID_TYPES.each do |pair|
        k, regex = pair
        if k == "doi" and regex.match(guid)
          url = "https://api.openalex.org/works/doi:#{guid}"
          return ["doi", url]
        end
      end
      [nil, nil]
    end
  end
end
