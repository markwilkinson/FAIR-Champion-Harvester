# frozen_string_literal: true

module FAIRChampionHarvester
  # Collects every typed link a resource advertises (HTTP Link headers and
  # HTML <link> elements), without filtering on rel. Core.parse_link_http_headers
  # only keeps the handful of rels that point at metadata; service discovery
  # (FAIRiCat api-catalog, OAI-PMH endpoints, ...) needs the rest.
  class LinkHints
    # <url>; rel="x"; type="y"  — tolerant of commas inside the URL and of
    # several links sharing one header value.
    LINK_VALUE = /<([^>]*)>((?:\s*;\s*[\w*-]+\s*=\s*(?:"[^"]*"|[^;,\s]*))*)/
    LINK_PARAM = /;\s*([\w*-]+)\s*=\s*(?:"([^"]*)"|([^;,\s]*))/

    # @param headers [HTTP::Headers, Hash, nil]
    # @param base [String] URL the headers were received from (for relative hrefs)
    # @return [Array<Hash>] {href:, rel:, type:, profile:, title:, via:}
    def self.from_headers(headers, base)
      return [] unless headers

      values = headers.respond_to?(:get) ? headers.get("Link") : Array(headers[:link] || headers["Link"])
      Array(values).flat_map { |value| value.to_s.scan(LINK_VALUE) }.filter_map do |href, params|
        attrs = params.scan(LINK_PARAM).to_h { |k, quoted, bare| [k.downcase, quoted || bare] }
        next unless attrs["rel"]

        build(href, attrs, base, "Link header")
      end
    end

    def self.from_html(body, base, content_type: nil)
      return [] if body.nil? || body.empty?
      return [] if content_type && !content_type.to_s.match?(%r{html|xml}i)

      Nokogiri::HTML(body).css("link[href][rel]").filter_map do |node|
        attrs = { "rel" => node["rel"], "type" => node["type"], "title" => node["title"], "profile" => node["profile"] }
        build(node["href"], attrs, base, "HTML link")
      end
    rescue StandardError
      []
    end

    def self.build(href, attrs, base, via)
      absolute = absolutize(href.to_s.strip, base)
      return unless absolute

      # rel may hold several space-separated relation types
      { href: absolute, rels: attrs["rel"].to_s.downcase.split, type: attrs["type"]&.strip,
        profile: attrs["profile"]&.strip, title: attrs["title"], via: via }
    end
    private_class_method :build

    def self.absolutize(href, base)
      return nil if href.empty?

      uri = URI.join(base.to_s, href)
      uri.to_s if %w[http https].include?(uri.scheme)
    rescue URI::Error
      nil
    end
  end
end
