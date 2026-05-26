## [Unreleased]

## [0.1.11] - 2026-05-26

### Fixed
- `lib/uri.rb` was shadowing Ruby's stdlib `require "uri"` because `lib/` is on the load path; moved `FAIRChampionHarvester::Uri` class to `lib/uri_resolver.rb` and turned `lib/uri.rb` into a stdlib-forwarding shim — this was the root cause of all HTTP fetch failures (`uninitialized constant URI`)
- `parse_link_http_headers`: handle multiple separate `Link:` headers (Array input) in addition to comma-separated single-string headers, using `Array(links).flat_map { |l| l.split(",") }`
- `parse_link_http_headers`: `rel` regex `\w+` → `[\w-]+` so hyphenated rel types like `cite-as` are captured correctly rather than silently truncated
- `parse_link_http_headers`: added `next unless url` guard against nil URLs; tightened URL regex to non-greedy `<([^>]*)>`
- `parse_link_http_headers`: added `describedby` to the allowlist alongside `meta` and `alternate`
- `parse_link_body_headers`: `link_nodes << NodeSet` → `link_nodes + NodeSet` (NodeSet concatenation); the old `<<` raised `ArgumentError: node must be a Nokogiri::XML::Node`
- `simplefetch`: corrected copy-paste bug where `guid` was referenced instead of `url` parameter
- `Core.fetch`: backtrace now always logged on `StandardError` (removed `if ENV["DEBUG"]` guard)

### Added
- RSpec test suite with 14 unit tests for `parse_link_http_headers` and 6 live integration tests against `https://fairsharing.org/1547`; live tests clear stale `/tmp/*_error` cache files before each run

## [0.1.10] - 2026-05-26

- variable url was not defined, but caught by begin block so no complaints


## [0.1.0] - 2026-03-27

- Initial release
