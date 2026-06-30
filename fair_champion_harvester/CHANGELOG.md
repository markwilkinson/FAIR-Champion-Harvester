# Changelog

## [Unreleased]

## [0.1.14] - 2026-06-30

### Fixed

- Critical cache collision bug in `Cache.checkRDFCache`: the lookup was comparing only `File.size == body.bytesize` (byte count) against every `*_graphbody` file in `/tmp`, while `writeRDFCache` had always written files keyed by `MD5(body)`. As `/tmp` accumulated files over days of running, any two metadata bodies with identical byte counts would collide — the wrong RDF graph would be returned for a request. Symptom: a completely unrelated dataset's metadata (e.g. "Tata Motors NSE OHLCV Dataset") returned for a different resource (e.g. Glasgow University ORDA record). Problem disappeared on restart (clears `/tmp`) but returned after ~1 week. Fixed by rewriting `checkRDFCache` to look up directly by `MD5(body)` — O(1), no glob scan, and consistent with the write path. Also eliminates the parallel-access race window where a thread could match a partially-written file from another thread.

## [0.1.13] - 2026-06-30

### Fixed

- JSON-LD documents with a remote `@context` (e.g. `"@context": "http://schema.org"`) were not having their context resolved, so properties like `license` that carry `"@type": "@id"` in the schema.org context were being parsed as string literals instead of IRI resources. This caused FAIR license assessment tests to warn "Found the Schema license predicate, but it does not have a Resource as its value." Fixed by routing JSON-LD through `JSON::LD::API.expand` (processing mode 1.1) before conversion to RDF, which applies `@type: @id` coercions. `json/ld/preloaded` (already required) supplies schema.org and other common contexts without network overhead.
- Array-wrapped JSON-LD (a top-level JSON array, as returned by extruct and some APIs) no longer raises `TypeError: no implicit conversion of String into Integer` during the context debug log.
- Added graceful fallback: if JSON-LD context expansion raises `JSON::LD::JsonLdError`, the document is re-parsed without expansion and a warning is recorded rather than failing silently.

### Added

- RSpec unit tests for `parse_rdf` JSON-LD path: license IRI coercion, successful expansion comment, array-wrapped document handling.

## [0.1.12] - 2026-05-27

### Fixed

- 0.1.11 regression: `FAIRChampionHarvester::Uri` was missing from the gem because `uri_resolver.rb` was not tracked by git and the gemspec uses `git ls-files` to determine packaged files; merged the class back into `lib/uri.rb` so a single tracked file handles both stdlib forwarding and the class definition

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
