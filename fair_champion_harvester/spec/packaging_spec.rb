# frozen_string_literal: true

# The gemspec packages `git ls-files`, so a new file that is not yet tracked is
# silently left out of the built gem and only fails at runtime in the consumer
# (0.1.18 shipped without lib/link_hints.rb this way).
RSpec.describe "gem packaging" do
  let(:root) { File.expand_path("..", __dir__) }
  let(:spec) { Gem::Specification.load(File.join(root, "fair_champion_harvester.gemspec")) }

  it "includes every file under lib/" do
    on_disk = Dir.chdir(root) { Dir.glob("lib/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) } }
    expect(on_disk - spec.files).to eq([]), "untracked files missing from the gem (git add them): #{on_disk - spec.files}"
  end

  it "includes the extruct User-Agent shim" do
    expect(spec.files).to include("lib/python/sitecustomize.py")
  end
end
