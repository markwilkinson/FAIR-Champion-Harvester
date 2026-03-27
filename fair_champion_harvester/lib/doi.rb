module FAIRChampionHarvester
  class DOI
    def self.resolve_doi(guid, meta)
      guid.downcase!
      type, url = Core.convertToURL(guid)
      meta.guidtype = type if meta.guidtype.nil?
      meta.comments << "INFO:  Found a DOI.\n"

      meta.comments << "INFO:  Attempting to resolve #{url} using HTTP Headers #{FAIRChampionHarvester::Utils::AcceptHeader}.\n"
      FAIRChampionHarvester::URL.resolve_url(guid: url, meta: meta, nolinkheaders: false) # specifically metadataguid: link, meta: meta, nolinkheaders: true
      meta.comments << "INFO:  Attempting to resolve #{url} using HTTP Headers {\"Accept\"=>\"*/*\"}.\n"
      FAIRChampionHarvester::URL.resolve_url(guid: url, meta: meta, nolinkheaders: false, headers: { "Accept" => "*/*" }) # whatever is default

      # CrossRef and DataCite both "intercept" the normal redirect process, when a URI has a content-type
      # Accept header that they understand.  This prevents the owner of the data from providing their own
      # metadata of that type, when using the DOI as their GUID.  Here
      # we have let the redirect process go all the way to the final URL, and we then
      # treat that as a new GUID.
      finalURI = meta.finalURI.last
      if finalURI =~ %r{\w+://}
        meta.comments << "INFO:  DOI resolution captures content-negotiation before reaching final data owner.  Now re-attempting the full suite of content negotiation on final redirect URI #{finalURI}.\n"
        FAIRChampionHarvester::Uri.resolve_uri(finalURI, meta)
      end

      meta
    end

    # this should only be called AFTER the general resolve above
    def self.resolve_doi_to_registration_agency(doi, meta)
      doi.downcase!
      doi.gsub!(%r{https?://[^/+]/}, "")
      doi.strip!
      url = "https://doi.org/doiRA/#{doi}"
      meta.comments << "INFO:  Finding DOI registration agency.\n"

      meta.comments << "INFO:  Attempting to resolve #{url} using HTTP Headers {\"Accept\"=>\"*/*\"}.\n"
      _headers, body = Core.fetch(guid: url, headers: FAIRChampionHarvester::Utils::AcceptDefaultHeader)
      if body
        meta.comments << "INFO:  parsing agency from response\n"
        json = JSON.parse(body)
        json.dig(0, "RA")
      else
        meta.comments << "WARN:  doiRA did not return JSON.  Aborting.\n"
        false
      end
    end

    def self.get_funding_information_from_crossref(doi, meta)
      # https://api.crossref.org/works/10.1063/5.0095229
      doi.downcase!
      doi.gsub!(%r{https?://[^/+]/}, "")
      doi.strip!
      url = "https://api.crossref.org/works/#{doi}"
      meta.comments << "INFO:  Looking for funding information\n"
      _headers, body = Core.fetch(guid: url, headers: FAIRChampionHarvester::Utils::AcceptDefaultHeader)
      return false unless body

      meta.comments << "INFO:  parsing funding info from response\n"
      json = JSON.parse(body)
      funding_refs = json.dig("message", "funder")
      first_funding = funding_refs&.dig(0) # safe navigation + dig

      if first_funding
        meta.comments << "INFO:  funding info block found\n"
        first_funding
      else
        meta.comments << "WARN:  no funding information block found\n"
        false
      end
    end

    def self.get_funding_information_from_datacite(doi, meta)
      # https://api.datacite.org/dois/10.15151/ESRF-ES-2303075148
      doi.downcase!
      doi.gsub!(%r{https?://[^/+]/}, "")
      doi.strip!
      url = "https://api.datacite.org/dois/#{doi}"
      meta.comments << "INFO:  Looking for funding information\n"
      _headers, body = Core.fetch(guid: url, headers: FAIRChampionHarvester::Utils::AcceptDefaultHeader)
      return false unless body

      # warn body

      meta.comments << "INFO:  parsing funding info from response\n"
      data = JSON.parse(body)

      funding_refs = data.dig("data", "attributes", "fundingReferences")
      first_funding = funding_refs&.dig(0) # safe navigation + dig

      if first_funding
        meta.comments << "INFO:  funding info block found\n"
        first_funding
      else
        meta.comments << "WARN:  no funding information block found\n"
        false
      end
    end

    def self.check_affiliation_information_from_crossref(doi, meta)
      # https://api.crossref.org/works/10.1063/5.0095229
      doi.downcase!
      doi.gsub!(%r{https?://[^/+]/}, "")
      doi.strip!
      url = "https://api.crossref.org/works/#{doi}"
      meta.comments << "INFO:  Looking for affiliation information\n"
      _headers, body = Core.fetch(guid: url, headers: FAIRChampionHarvester::Utils::AcceptDefaultHeader)
      # warn "headers #{_headers} #{url}"
      # abort
      return false unless body

      # normal author
      meta.comments << "INFO:  parsing affiliation info from response\n"
      json = JSON.parse(body)
      auths = json.dig("message", "author")
      auths&.each do |auth|
        if auth["affiliation"]&.first # cant be empty list
          meta.comments << "INFO:  At least one author has affiliation information\n"
          return true
        end
      end

      # grant author
      # "investigator": [
      #           {
      #             "given": "Manka",
      #             "family": "Varghese",
      #             "affiliation": [
      #               {
      #                 "name": "University of Washington"
      #               }
      #             ]
      #           },
      # ...

      #  "lead-investigator": [
      #           {
      #             "given": "Jessica",
      #             "family": "Thompson",
      #             "affiliation": [
      #               {
      #                 "name": "University of Washington"
      #               }
      #             ]
      #           }
      #         ],
      meta.comments << "INFO:  checking for investigator or lead investigator in grant information\n"
      json = JSON.parse(body)
      projects = json.dig("message", "project") # returns a list
      projects&.each do |proj|
        investigators = proj["investigator"] # two possibilities
        investigators << proj["lead-investigator"]
        investigators&.each do |inv|
          if inv["affiliation"]&.first
            meta.comments << "INFO:  At least one investigator has affiliation information\n"
            return true
          end
        end
      end

      meta.comments << "WARN:  no authors had affiliation information\n"
      false
    end

    def self.check_affiliation_information_from_datacite(doi, meta)
      # https://api.datacite.org/dois/10.15151/ESRF-ES-2303075148
      doi.downcase!
      doi.gsub!(%r{https?://[^/+]/}, "")
      doi.strip!
      url = "https://api.datacite.org/dois/#{doi}"
      meta.comments << "INFO:  Looking for author affiliation information\n"
      _headers, body = Core.fetch(guid: url, headers: FAIRChampionHarvester::Utils::AcceptDefaultHeader)
      return false unless body

      # warn body

      meta.comments << "INFO:  parsing affiliation info from response\n"
      data = JSON.parse(body)

      auths = data.dig("data", "attributes", "creators")
      auths&.each do |auth|
        if auth["affiliation"]
          meta.comments << "INFO:  At least one author has affiliation information\n"
          return true
        end
      end
      meta.comments << "WARN:  no authors had affiliation information\n"
      false
    end

    def self.check_license_information_from_datacite(doi, meta)
      # https://api.datacite.org/dois/10.15151/ESRF-ES-2303075148
      doi.downcase!
      doi.gsub!(%r{https?://[^/+]/}, "")
      doi.strip!
      url = "https://api.datacite.org/dois/#{doi}"
      meta.comments << "INFO:  Looking for license information\n"
      _headers, body = Core.fetch(guid: url, headers: FAIRChampionHarvester::Utils::AcceptDefaultHeader)
      return false unless body

      # warn body

      meta.comments << "INFO:  parsing license info from response\n"
      data = JSON.parse(body)

      rights = data.dig("data", "attributes", "rightsList") # may return empty list - for a fail
      if rights&.first
        meta.comments << "INFO:  license information found\n"
        return true
      end
      meta.comments << "WARN:  no license information found\n"
      false
    end

    def self.check_license_information_from_crossref(doi, meta)
      # https://api.crossref.org/works/10.1063/5.0095229
      doi.downcase!
      doi.gsub!(%r{https?://[^/+]/}, "")
      doi.strip!
      url = "https://api.crossref.org/works/#{doi}"
      meta.comments << "INFO:  Looking for license information\n"
      _headers, body = Core.fetch(guid: url, headers: FAIRChampionHarvester::Utils::AcceptDefaultHeader)
      # warn "headers #{_headers} #{url}"
      # abort
      return false unless body

      # normal author
      meta.comments << "INFO:  parsing license info from response\n"
      json = JSON.parse(body)
      lics = json.dig("message", "license")
      if lics&.first
        meta.comments << "INFO:  found license information\n"
        return true
      end
      meta.comments << "WARN:  no licsense information found\n"
      false
    end
  end
end
