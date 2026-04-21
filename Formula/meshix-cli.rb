class MeshixCli < Formula
  desc "Meshix CLI for run inspection and generation workflows"
  homepage "https://github.com/shpitdev/meshix-observability"
  version "0.0.1"
  license :cannot_represent
  depends_on arch: :arm64

  on_macos do
    on_arm do
      url "https://github.com/shpitdev/meshix-observability/releases/download/v0.0.1/meshix-cli_v0.0.1_darwin_arm64.tar.gz"
      sha256 "01e42197ff960a8f6033f80178800f8ede31bb8e18e276f705abc72b17ba7426"
    end
  end

  def install
    bin.install "meshix-cli"
  end

  def caveats
    <<~EOS
      Package-manager installs provide the stable meshix-cli command only.
      Start with:
        meshix-cli --help

      For a checkout-linked dev command, install meshix-cli-dev from a local checkout.
    EOS
  end

  test do
    output = shell_output("#{bin}/meshix-cli --help")
    assert_match "meshix-cli", output
    assert_match "architecture", output
  end
end
