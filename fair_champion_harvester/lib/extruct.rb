module FAIRChampionHarvester
  class Extruct
    BINARY_CONTENT_TYPE = %r{
      application/pdf|application/octet-stream|
      image/|audio/|video/|
      application/zip|application/gzip|application/x-tar|
      application/msword|application/vnd\.
    }ix
    BINARY_MAGIC_BYTES = /\A(%PDF|PK\x03\x04|GIF8|\x89PNG|\xFF\xD8\xFF|\xD0\xCF|\x1F\x8B)/n

    # Hard ceiling, in seconds, on how long the external `extruct` process may
    # run. The content-type and magic-byte checks above catch most binary
    # responses, but not all of them (unreliable/missing headers, formats
    # outside BINARY_MAGIC_BYTES, or just very large/slow-to-parse HTML) —
    # without this, a single such request blocks the calling thread (and
    # leaks an orphaned Python process) indefinitely. Configurable via
    # EXTRUCT_TIMEOUT_SECONDS.
    TIMEOUT_SECONDS = ENV.fetch("EXTRUCT_TIMEOUT_SECONDS", 30).to_i

    def self.do_extruct(meta, uri, content_type: nil, body_prefix: nil)
      if content_type&.match?(BINARY_CONTENT_TYPE)
        meta.comments << "INFO: Skipping extruct for #{uri} — " \
                         "binary content-type '#{content_type}' is not HTML-parseable.\n"
        return
      end
      if body_prefix&.match?(BINARY_MAGIC_BYTES)
        meta.comments << "INFO: Skipping extruct for #{uri} — binary file signature detected in response body.\n"
        return
      end
      meta.comments << "INFO:  Using 'extruct' to try to extract metadata from return value (message body) of #{uri}.\n"
      warn "begin open3"
      # binding.pry
      # Pass argv as separate elements (not one interpolated string) so this
      # never goes through a shell — `uri` can be attacker/publisher-supplied
      # and must not be shell-interpolated — and prepend the `timeout`
      # coreutil so a hung/slow extruct process is forcibly killed (-k 5:
      # escalate to SIGKILL 5s after the initial SIGTERM if it's ignored)
      # instead of blocking this thread and leaking a child process forever.
      command_parts = Shellwords.split(FAIRChampionHarvester::Utils::ExtructCommand)
      stdout, stderr, status = Open3.capture3(
        "timeout", "-k", "5", TIMEOUT_SECONDS.to_s, *command_parts, uri
      )
      warn ""
      # sleep 5
      warn "open3 status: #{status} #{stdout}"

      if [124, 137].include?(status.exitstatus)
        meta.comments << "WARN: extruct timed out after #{TIMEOUT_SECONDS}s parsing #{uri} — skipping.\n"
        return
      end

      result = stderr # absurd that the output comes over stderr!  LOL!

      # result = %x{#{FAIRChampionHarvester::Utils::ExtructCommand} #{uri} 2>&1}
      # $stderr.puts "\n\n\n\n\n\n\n#{result.class}\n\n#{result.to_s}\n\n#{@extruct_command} #{uri} 2>&1\n\n"
      # need to do some error checking here!
      if result.to_s.match(/(Failed\sto\sextract.*?)\n/)
        meta.comments << "WARN: extruct threw an error #{::Regexp.last_match(1)} when attempting to parse return value (message body) of #{uri}.\n"
        if result.to_s.match(/(ValueError:.*?)\n/)
          meta.comments << "WARN: extruct error was #{::Regexp.last_match(1)}\n"
        end
      elsif result.to_s.match(/^\s+?\{/) or result.to_s.match(/^\s+\[/) # this is JSON
        begin
          json = JSON.parse result
        rescue StandardError
          warn "json parsing failed!  This is bad!\n"
          meta.comments << "INFO: the extruct tool found non-parseable data at #{uri}.  Aborting attempt to read it\n"
          return
        end
        # $stderr.puts "\n\n\n\nFOUND JSON\n\n\n"
        # $stderr.puts "\n\n\n\nFOUND JSON-LD\n#{json["json-ld"]} content\n\n\n"
        meta.comments << "INFO: the extruct tool found parseable data at #{uri}\n"

        Core.parse_rdf(meta, json["json-ld"].to_json, "application/ld+json") if json["json-ld"].any? # RDF
        meta.merge_hash(json["microdata"].first) if json["microdata"].any?
        meta.merge_hash(json["microformat"].first) if json["microformat"].any?
        meta.merge_hash(json["opengraph"].first) if json["opengraph"].any?
        Core.parse_rdf(meta, json["rdfa"].to_json, "application/ld+json") if json["rdfa"].any? # RDF

        meta.merge_hash(json.first) if json.first.is_a? Hash
      else
        meta.comments << "WARN: the extruct tool failed to find parseable data at #{uri}\n"
      end
    end
  end
end
