# JSON-LD Context Expansion Fix — Handoff for Claude Code Integration

**Date:** 2026-06-30  
**Issue:** JSON-LD license properties being parsed as blank nodes instead of IRI resources  
**Root Cause:** Remote `@context` resolution not enabled in RDF reader instantiation  
**Impact:** FAIR assessment tests failing because `schema.org` license coercion (`@type: @id`) not applied

---

## Problem Summary

### What's Happening
When the FAIR Champion Harvester encounters JSON-LD with `"@context": "http://schema.org"` and `"license": "https://creativecommons.org/licenses/by/4.0/legalcode"`:

1. **Expected behavior:** JSON-LD processor fetches schema.org context, sees `license` has `"@type": "@id"`, coerces the URL string to an IRI resource
2. **Actual behavior:** Parser treats license as a bare string literal, or normalizes it into a blank node structure during serialization

### Why It Fails
The current `parse_rdf` method in `FAIRChampionHarvester` uses:
```ruby
reader = formattype.reader.new(body)
meta.merge_rdf(reader.to_a)
```

This instantiates `JSON::LD::Reader` with **no processing options**, so:
- Remote `@context` URLs are **not fetched** (security/performance default)
- JSON-LD expansion rules are **not applied**
- `@type: @id` coercions don't happen
- Bare string IRIs stay as literals

### Real-World Impact
ESRF dataset metadata has:
```json
{
  "@context": "http://schema.org",
  "license": "https://creativecommons.org/licenses/by/4.0/legalcode"
}
```

Without context expansion → license becomes a literal string or blank node → FAIR license test fails with warning:
```
WARN: Found the Schema license predicate, but it does not have a Resource as its value.
```

---

## Solution: Enable JSON-LD Expansion with Remote Context Resolution

### Key Code Decisions

**Decision 1: Format-specific handling**
- JSON-LD gets special treatment: use `JSON::LD::API.expand()` + `toRdf()` pipeline
- Other RDF formats (Turtle, N-Triples, RDF/XML) use existing reader pattern
- Rationale: Only JSON-LD needs context resolution; other formats are already RDF

**Decision 2: Processing options**
```ruby
processingOptions: {
  processingMode: 'json-ld-1.1',           # CRITICAL: 1.0 mode has weaker @type: @id semantics
  documentLoader: JSON::LD::DocumentLoader.new  # Explicitly enable remote context fetching
}
```
- `processingMode: 'json-ld-1.1'` ensures `@type: @id` is properly applied (1.0 had edge cases)
- `documentLoader.new` explicitly enables fetching of remote `@context` URIs (may be disabled by default)

**Decision 3: Graceful fallback**
- If remote context resolution fails (network, malformed URI), catch `JSON::LD::ProcessingError`
- Attempt parsing without expansion as fallback
- Log warning so operator knows context wasn't resolved
- Rationale: Metadata is still parseable as plain RDF even without context; better to get something than fail completely

**Decision 4: Cache interaction**
- Continue using existing `FAIRChampionHarvester::Cache` for non-JSON-LD formats
- For JSON-LD, cache the **raw body**, not the reader (reader is stateful, hard to serialize)
- After expansion, the RDF graph is cached via normal merge process
- Rationale: Keeps cache simple; re-expansion is cheap

---

## Implementation Strategy

### File to Modify
`lib/fair_champion_harvester/evaluator.rb` (or wherever `parse_rdf` method lives)

### Change Scope
- **Lines affected:** Reader instantiation block (approximately where `formattype.reader.new(body)` appears)
- **Methods touched:** `parse_rdf` static method
- **New requires:** `require 'json/ld'` (add at top of method or class)
- **No breaking changes:** Falls back to existing behavior if JSON-LD expansion fails

### Integration Checklist
- [ ] Locate `parse_rdf` method definition
- [ ] Add `require 'json/ld'` at method start or class level
- [ ] Replace simple reader pattern with format-aware conditional
- [ ] Test against ESRF metadata (original + expanded forms)
- [ ] Verify license triple is now IRI resource, not literal
- [ ] Run FAIR license assessment test — should pass or show nuanced result
- [ ] Check cache hit/miss behavior for JSON-LD documents
- [ ] Monitor for JSON::LD::ProcessingError in production logs

---

## Code Structure: What Gets Added

### Before (Current)
```ruby
reader = formattype.reader.new(body)
if reader.size == 0
  # handle empty graph
end
reader = formattype.reader.new(body)
FAIRChampionHarvester::Cache.writeRDFCache(reader, body)
reader = formattype.reader.new(body)
meta.merge_rdf(reader.to_a)
```

### After (Proposed)
```ruby
if formattype.to_s.include?('JSON::LD')
  # JSON-LD: expand with remote context resolution
  json_body = JSON.parse(body)
  
  expanded = JSON::LD::API.expand(json_body, processingOptions: {
    processingMode: 'json-ld-1.1',
    documentLoader: JSON::LD::DocumentLoader.new
  })
  
  graph = RDF::Graph.new
  JSON::LD::API.toRdf(expanded) do |statement|
    graph << statement
  end
  
  meta.merge_rdf(graph.to_a)
  FAIRChampionHarvester::Cache.writeRDFCache(graph, body)  # cache expanded RDF
else
  # Turtle, N-Triples, RDF/XML, etc: use standard reader
  reader = formattype.reader.new(body)
  
  if reader.size == 0
    meta.comments << "WARN: Though linked data was found, it failed to parse...\n"
    return meta
  end
  
  reader = formattype.reader.new(body)
  FAIRChampionHarvester::Cache.writeRDFCache(reader, body)
  reader = formattype.reader.new(body)
  meta.merge_rdf(reader.to_a)
end
```

### Error Handling
Wrap in `rescue JSON::LD::ProcessingError` to catch context resolution failures:
```ruby
rescue JSON::LD::ProcessingError => e
  meta.comments << "WARN: JSON-LD context resolution failed: #{e.message}\n"
  # Try fallback: parse without expansion
  begin
    reader = formattype.reader.new(body)
    meta.merge_rdf(reader.to_a)
    meta.comments << "WARN: Parsed JSON-LD without remote context resolution. Results may be incomplete.\n"
  rescue => fallback_error
    meta.comments << "CRITICAL: JSON-LD parsing failed even without context expansion: #{fallback_error.message}\n"
  end
```

---

## Validation: How to Test the Fix

### Unit Test: ESRF Metadata
```ruby
# Test with the original ESRF JSON-LD
json_body = JSON.parse(File.read('spec/fixtures/esrf_dataset.jsonld'))

expanded = JSON::LD::API.expand(json_body, processingOptions: {
  processingMode: 'json-ld-1.1',
  documentLoader: JSON::LD::DocumentLoader.new
})

graph = RDF::Graph.new
JSON::LD::API.toRdf(expanded) { |stmt| graph << stmt }

# Check license triple
license_triples = graph.query([nil, RDF::URI('http://schema.org/license'), nil])
license_triples.each do |stmt|
  expect(stmt.object.resource?).to be true
  expect(stmt.object.anonymous?).to be false
  expect(stmt.object.to_s).to eq 'https://creativecommons.org/licenses/by/4.0/legalcode'
end
```

### Integration Test: FAIR Assessment
Run your existing FAIR license test against the fixed harvester:
```ruby
result = FAIRChampionHarvester.evaluate('https://doi.org/10.15151/esrf-es-2210534378')

# Should now pass (or at least not complain about literal value)
expect(result.output.score).to eq 'pass'
expect(result.output.comments).to include('SUCCESS: Found the Schema license predicate with a Resource')
```

### Diagnostic Output
Add debug logging to trace expansion:
```ruby
warn "JSON-LD Expansion: Input has #{json_body.keys.length} root keys"
warn "JSON-LD Expansion: Context is #{json_body['@context']}"
expanded = JSON::LD::API.expand(json_body, processingOptions: {...})
warn "JSON-LD Expansion: Output has #{expanded.length} objects"
```

---

## Performance Considerations

### Remote Context Fetching
- **Latency:** First fetch of `http://schema.org` context takes ~200-500ms
- **Caching:** Ruby's `json-ld` gem caches fetched contexts in memory — subsequent documents are fast
- **Network:** Single HTTP GET per unique `@context` URL per process lifetime
- **Recommendation:** OK for production; consider warm-up if processing high volume at startup

### JSON-LD Expansion
- **CPU:** Expansion is O(n) in document size; typically <50ms for datasets
- **Memory:** Expanded form is usually 1.5-2x original size
- **Recommendation:** Acceptable; RDF graph construction is already expensive

### Cache Strategy
- Cache the **expanded RDF graph**, not the raw JSON-LD
- This way, subsequent accesses skip expansion
- For documents with same `@context`, expansion is cached by `json-ld` gem anyway

---

## Known Limitations & Edge Cases

### 1. Custom or Malformed Contexts
If a document's `@context` URL returns 404 or invalid JSON, expansion will fail.
- **Mitigation:** Fallback to parsing without expansion (implemented in error handler)
- **Log:** Warning message indicates context couldn't be resolved

### 2. Blank Nodes vs. Named Resources
Schema.org allows some properties to be blank nodes. Example: a license as a `CreativeWork` object.
```json
{
  "license": {
    "@type": "CreativeWork",
    "name": "CC-BY",
    "url": "https://creativecommons.org/licenses/by/4.0/"
  }
}
```
- **Current test logic:** Rejects blank nodes (`!object.anonymous?`)
- **Better approach:** Accept blank nodes IF they have properties; only fail on bare string literals
- **Future refinement:** Update license test to differentiate:
  - Named resource IRI (best)
  - Anonymous resource with properties (good)
  - String literal (warn)

### 3. Context Conflicts
If document has both `"@context": "http://schema.org"` and inline context definitions, inline wins.
- **Expected behavior:** This is JSON-LD spec-compliant
- **No action needed:** Rare in practice

---

## Debugging Tips for Claude Code Session

### If License Still Appears as Literal
1. Check if `JSON::LD::API.expand()` is actually being called
   - Add `warn "Expanding JSON-LD with schema.org context"`
2. Verify documentLoader is enabled:
   - Try adding `documentLoader: JSON::LD::DocumentLoader.new` explicitly
3. Check if remote context is actually fetching:
   - Try: `context = JSON.parse(Net::HTTP.get(URI('https://schema.org/docs/jsonldcontext.json')))`
   - If that times out, network issue; if it parses, `json-ld` gem should too

### If Blank Nodes Still Appear
- Check if license is nested structure: `{ "@type": "CreativeWork", ... }`
- If so, that's valid RDF; update FAIR test to accept anonymous resources with properties
- If it's a bare blank node with no properties, something is still wrong with expansion

### If Context Resolution Fails
- Check gem version: `bundle show json-ld`
- Ensure `json-ld >= 3.2.0` (older versions had weaker context support)
- Try manually: `JSON::LD::API.expand(json_body, processingOptions: { documentLoader: JSON::LD::DocumentLoader.new })`
- Check network: Can you reach `http://schema.org` from the runtime environment?

---

## Commit Message Template

```
Fix: Enable JSON-LD context expansion for remote @context resolution

- Add processingMode: 'json-ld-1.1' to apply @type: @id coercions
- Enable documentLoader for remote context fetching (schema.org, etc.)
- Separate JSON-LD handling from other RDF formats
- Add graceful fallback if context resolution fails
- Resolves: License properties now correctly expanded as IRI resources
- Tested against: ESRF dataset metadata with schema.org context

Fixes #ISSUE_NUMBER (if applicable)
```

---

## References

- **JSON-LD 1.1 Spec:** https://www.w3.org/TR/json-ld11/
- **schema.org context:** https://schema.org/docs/jsonldcontext.json
- **ruby json-ld gem:** https://github.com/ruby-rdf/json-ld
- **schema.org license property:** https://schema.org/license
- **FAIR license assessment:** Your FAIR test queries for `http://schema.org/license` with `@type: @id`

