# frozen_string_literal: true

# This file is named uri.rb, which means Ruby's load path resolves
# 'require "uri"' here instead of the stdlib. We forward to the real one.
require File.join(RbConfig::CONFIG["rubylibdir"], "uri")
