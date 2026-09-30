# frozen_string_literal: true

require "webmock"
require "webmock/rspec/matchers"

# Shared helpers for specs that exercise HTTP without touching the network.
#
# WebMock is enabled only around the examples that ask for it (:http), because
# the :live examples in this suite need real connections.
module HttpSpecSupport
  include WebMock::API
  include WebMock::Matchers

  OAI_NS = 'xmlns="http://www.openarchives.org/OAI/2.0/"'

  def oai_envelope(inner, verb: "Identify")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <OAI-PMH #{OAI_NS}>
        <responseDate>2026-01-01T00:00:00Z</responseDate>
        <request verb="#{verb}">https://repo.example.org/oai</request>
        #{inner}
      </OAI-PMH>
    XML
  end

  def identify_xml(repo_id: "repo.example.org", sample: "oai:repo.example.org:12345")
    oai_envelope(<<~XML)
      <Identify>
        <repositoryName>Example Repository</repositoryName>
        <protocolVersion>2.0</protocolVersion>
        <description>
          <oai-identifier xmlns="http://www.openarchives.org/OAI/2.0/oai-identifier">
            <scheme>oai</scheme>
            <repositoryIdentifier>#{repo_id}</repositoryIdentifier>
            <delimiter>:</delimiter>
            <sampleIdentifier>#{sample}</sampleIdentifier>
          </oai-identifier>
        </description>
      </Identify>
    XML
  end

  def get_record_xml(identifier, title: "A Test Dataset")
    oai_envelope(<<~XML, verb: "GetRecord")
      <GetRecord>
        <record>
          <header><identifier>#{identifier}</identifier><datestamp>2026-01-01</datestamp></header>
          <metadata>
            <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/"
                       xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:title>#{title}</dc:title>
              <dc:creator>Doe, Jane</dc:creator>
              <dc:identifier>https://doi.org/10.1234/abc</dc:identifier>
            </oai_dc:dc>
          </metadata>
        </record>
      </GetRecord>
    XML
  end

  def list_formats_xml(*prefixes)
    formats = prefixes.map { |p| "<metadataFormat><metadataPrefix>#{p}</metadataPrefix></metadataFormat>" }.join
    oai_envelope("<ListMetadataFormats>#{formats}</ListMetadataFormats>", verb: "ListMetadataFormats")
  end

  def oai_error_xml(code)
    oai_envelope(%(<error code="#{code}">nope</error>), verb: "GetRecord")
  end
end

RSpec.shared_context "with stubbed HTTP" do
  include HttpSpecSupport

  before do
    WebMock.enable!
    WebMock.reset!
    # Core.fetch caches to /tmp; keep specs independent of it and of each other
    allow(FAIRChampionHarvester::Cache).to receive(:checkCache).and_return(nil)
    allow(FAIRChampionHarvester::Cache).to receive(:writeToCache)
    allow(FAIRChampionHarvester::Cache).to receive(:writeErrorToCache)
  end

  after do
    WebMock.reset!
    WebMock.disable!
  end
end
