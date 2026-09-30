# frozen_string_literal: true

require "open3"
require "socket"
require_relative "support_http"

RSpec.describe "harvester User-Agent" do
  let(:ua) { "fair-champion-tests-harvester" }

  it "defaults to a distinct, unversioned identifier" do
    expect(FAIRChampionHarvester::Utils::UserAgent).to eq(ENV.fetch("HARVESTER_USER_AGENT", ua))
    expect(FAIRChampionHarvester::Utils::UserAgentHeader).to eq("User-Agent" => FAIRChampionHarvester::Utils::UserAgent)
  end

  context "with stubbed HTTP" do
    include_context "with stubbed HTTP"

    let(:expected) { FAIRChampionHarvester::Utils::UserAgent }

    it "is sent by Core.fetch" do
      stub = stub_request(:get, "https://repo.example.org/a").with(headers: { "User-Agent" => expected }).to_return(body: "x")
      FAIRChampionHarvester::Core.fetch(guid: "https://repo.example.org/a")
      expect(stub).to have_been_requested
    end

    it "is sent by Core.simplefetch" do
      stub = stub_request(:get, "https://repo.example.org/b").with(headers: { "User-Agent" => expected }).to_return(body: "x")
      FAIRChampionHarvester::Core.simplefetch("https://repo.example.org/b")
      expect(stub).to have_been_requested
    end

    it "is sent on redirects that Core.fetch follows" do
      stub_request(:get, "https://repo.example.org/r1").to_return(status: 302, headers: { "Location" => "https://repo.example.org/r2" })
      final = stub_request(:get, "https://repo.example.org/r2").with(headers: { "User-Agent" => expected }).to_return(body: "x")
      FAIRChampionHarvester::Core.fetch(guid: "https://repo.example.org/r1")
      expect(final).to have_been_requested
    end

    it "still sends the Accept header the caller asked for" do
      stub = stub_request(:get, "https://repo.example.org/c")
             .with(headers: { "User-Agent" => expected, "Accept" => "text/turtle" }).to_return(body: "x")
      FAIRChampionHarvester::Core.fetch(guid: "https://repo.example.org/c", headers: { "Accept" => "text/turtle" })
      expect(stub).to have_been_requested
    end

    it "is not part of the cache key (the headers argument is unchanged)" do
      stub_request(:get, "https://repo.example.org/d").to_return(body: "x")
      accept = { "Accept" => "text/turtle" }
      FAIRChampionHarvester::Core.fetch(guid: "https://repo.example.org/d", headers: accept)
      expect(FAIRChampionHarvester::Cache).to have_received(:checkCache).with("https://repo.example.org/d", accept)
    end
  end

  describe "the extruct subprocess" do
    let(:shim_env) { FAIRChampionHarvester::Extruct.python_env }

    it "passes the User-Agent and the shim directory to the subprocess" do
      expect(shim_env["EXTRUCT_USER_AGENT"]).to eq(FAIRChampionHarvester::Utils::UserAgent)
      expect(shim_env["PYTHONPATH"].split(File::PATH_SEPARATOR)).to include(FAIRChampionHarvester::Extruct::PYTHON_SHIM_DIR)
      expect(File).to exist(File.join(FAIRChampionHarvester::Extruct::PYTHON_SHIM_DIR, "sitecustomize.py"))
    end

    it "keeps an existing PYTHONPATH" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("PYTHONPATH", nil).and_return("/opt/existing")
      expect(FAIRChampionHarvester::Extruct.python_env["PYTHONPATH"].split(File::PATH_SEPARATOR)).to end_with("/opt/existing")
    end

    def python_with_requests?
      _out, _err, status = Open3.capture3("python3", "-c", "import requests")
      status.success?
    rescue Errno::ENOENT
      false
    end

    it "makes python-requests use the harvester User-Agent" do
      skip "python3 with requests is not available" unless python_with_requests?
      out, _err, status = Open3.capture3(shim_env, "python3", "-c", "import requests; print(requests.Session().headers['User-Agent'])")
      expect(status).to be_success
      expect(out.strip).to eq(FAIRChampionHarvester::Utils::UserAgent)
    end

    it "leaves python-requests alone when EXTRUCT_USER_AGENT is unset" do
      skip "python3 with requests is not available" unless python_with_requests?
      env = shim_env.merge("EXTRUCT_USER_AGENT" => nil)
      out, = Open3.capture3(env, "python3", "-c", "import requests; print(requests.Session().headers['User-Agent'])")
      expect(out.strip).to start_with("python-requests/")
    end

    it "is what the real extruct CLI sends over the wire" do
      skip "extruct is not installed" unless system("which extruct > /dev/null 2>&1")
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      seen = Queue.new
      thread = Thread.new do
        client = server.accept
        request = +""
        while (line = client.gets) && line != "\r\n"
          request << line
        end
        seen << request
        client.write "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\nConnection: close\r\n\r\n<html></html>"
        client.close
      end
      Open3.capture3(shim_env, "timeout", "30", "extruct", "http://127.0.0.1:#{port}/")
      thread.join(5)
      expect(seen.pop(true)).to match(/^User-Agent: #{Regexp.escape(FAIRChampionHarvester::Utils::UserAgent)}\r?$/i)
    ensure
      server&.close
    end
  end
end
