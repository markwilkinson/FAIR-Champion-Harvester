# #!/usr/bin/env ruby
# # encoding: UTF-8

# require 'doi'
# require 'oai'
# require 'nokogiri'
# require 'open-uri'
# require 'uri'

# # Function to discover repo and endpoint from DOI landing page
# def discover_repo_and_endpoint(doi_str)
#   begin
#     doi = DOI::URI.parse(doi_str)
#     landing_url = doi.to_s
#     puts "Resolved DOI to: #{landing_url}"

#     # Fetch landing page HTML
#     uri = URI(landing_url)
#     html = Nokogiri::HTML(URI.open(uri))

#     # Extract repo domain from URL
#     repo_domain = uri.host.gsub(/^www\./, '')
#     puts "Repo domain: #{repo_domain}"

#     # Look for OAI-PMH hints in <head> or links
#     oai_link = html.xpath('//link[@rel="search" and contains(@type, "opensearchdescription+xml") and contains(@title, "OAI")]/@href').text
#     if oai_link.empty?
#       # Fallback: Search common paths (customize per repo if needed)
#       common_paths = ['/oai', '/oai-pmh', '/oai2d', '/oaiprovider/request', '/api/oai']
#       oai_link = common_paths.find { |path| test_endpoint("#{uri.scheme}://#{repo_domain}#{path}") }
#     end

#     # Specific mappings (expand as needed)
#     endpoint = case repo_domain
#                when /zenodo.org/ then 'https://zenodo.org/oai2d'
#                when /dataverse.harvard.edu/ then 'https://dataverse.harvard.edu/oai'
#                when /figshare.com/ then 'https://figshare.com/oai'
#                else oai_link || guess_via_search(repo_domain)
#                end

#     # Extract record ID from landing path
#     path_segments = uri.path.split('/')
#     record_id = path_segments.last if path_segments.last =~ /^\d+$/  # e.g., '1234567'

#     { endpoint: endpoint, repo_domain: repo_domain, record_id: record_id }
#   rescue => e
#     puts "Discovery error: #{e.message} (falling back to DataCite aggregator)"
#     { endpoint: 'https://oai.datacite.org/oai', use_doi_as_id: true }
#   end
# end

# # Test if endpoint is valid (quick Identify check)
# def test_endpoint(url)
#   test_uri = URI(url + '?verb=Identify')
#   response = URI.open(test_uri) rescue nil
#   !response.nil? && Nokogiri::XML(response).xpath('//OAI-PMH').present?
# rescue
#   false
# end

# # Placeholder: Guess via external search (implement with API if needed, e.g., Google Custom Search)
# def guess_via_search(domain)
#   # In practice, query a search API or cache results
#   "https://#{domain}/oai"  # Default guess
# end

# # Main fetch function
# def fetch_oai_from_doi(doi_str, metadata_prefix = 'oai_dc')
#   discovery = discover_repo_and_endpoint(doi_str)
#   oai_id = if discovery[:use_doi_as_id]
#              doi_str
#            else
#              "oai:#{discovery[:repo_domain]}:#{discovery[:record_id]}"
#            end

#   puts "Inferred OAI ID: #{oai_id}"
#   puts "Endpoint: #{discovery[:endpoint]}"

#   begin
#     client = OAI::Client.new(discovery[:endpoint])
#     record = client.get_record(identifier: oai_id, metadata_prefix: metadata_prefix)

#     metadata = record.metadata
#     puts "\n--- Metadata Excerpt ---"
#     puts "Title: #{metadata['title']&.first || 'N/A'}"
#     puts "Creator: #{metadata['creator']&.join(', ') || 'N/A'}"
#     puts "DOI: #{metadata['identifier']&.find { |id| id.include?('doi.org') } || 'N/A'}"
#     puts "Full XML:\n#{record.to_xml[0..500]}..."  # Truncated

#     return record
#   rescue OAI::NoRecordsMatch => e
#     puts "No match: #{e.message} (Try publishing the record or check ID)"
#   rescue => e
#     puts "Error: #{e.message}"
#   end
# end

# # Example: Zenodo DOI
# fetch_oai_from_doi('10.5281/zenodo.1234567', 'datacite')  # Replace with real DOI
