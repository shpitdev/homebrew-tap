class Tabex < Formula
  desc "Tabex CLI for browser session, capture, and page inspection"
  homepage "https://github.com/shpitdev/tabex"
  version "0.0.55"
  license :cannot_represent
  depends_on arch: :arm64

  on_macos do
    on_arm do
      url "https://github.com/shpitdev/pkgbuilds/releases/download/tabex-v0.0.55/tabex_v0.0.55_darwin_arm64.tar.gz"
      sha256 "6c75a1e44060677724ccfbb95256f089724a65d91e4e913c53b939cad43b0b68"
    end
  end

  def install
    bin.install "tabex"
  end

  def caveats
    <<~EOS
      Tabex needs browser-profile and extension setup after install.
      Start with:
        tabex setup

      Install Tabex from the Chrome Web Store, then register and verify the
      local native enrollment host:
        tabex browser native-host install
        tabex browser native-host status
    EOS
  end

  test do
    require "json"

    payload = JSON.parse(shell_output("#{bin}/tabex --json"))
    assert_equal "tabex", payload["command"]
    assert_equal "tabex <command>", payload["usage"]
    assert_equal "v#{version}", payload["version"]
    assert_equal "docs/curated-e2e-examples.md", payload["curatedExamplesDoc"]
    assert_equal "setup", payload["startHere"].first["command"]
  end
end
