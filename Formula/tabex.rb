class TabexGitHubReleaseDownloadStrategy < CurlDownloadStrategy
  def initialize(url, name, version, **meta)
    @resolved_basename = meta.delete(:resolved_basename)
    @github_token = resolve_github_token

    if @github_token.nil? || @github_token.empty?
      raise CurlDownloadStrategyError.new(
        url,
        [
          "GitHub authentication is required to download the private tabex release asset.",
          "Set HOMEBREW_GITHUB_API_TOKEN, GH_TOKEN, or GITHUB_TOKEN,",
          "or log in with gh auth login. SHPIT_GH_TOKEN is also supported for SHPIT automation."
        ].join(" ")
      )
    end

    meta[:headers] ||= []
    meta[:headers] << "Accept: application/octet-stream"
    meta[:headers] << "Authorization: Bearer #{@github_token}"
    super
  end

  private

  def resolve_github_token
    %w[HOMEBREW_GITHUB_API_TOKEN GH_TOKEN GITHUB_TOKEN].each do |key|
      value = ENV[key]&.strip
      return value unless value.nil? || value.empty?
    end

    [
      "#{HOMEBREW_PREFIX}/bin/gh",
      "/opt/homebrew/bin/gh",
      "/usr/local/bin/gh",
      "gh"
    ].uniq.each do |gh|
      next if gh != "gh" && !File.executable?(gh)

      value = Utils.safe_popen_read(gh, "auth", "token").strip
      return value unless value.empty?
    rescue ErrorDuringExecution, Errno::ENOENT
      next
    end

    value = ENV["SHPIT_GH_TOKEN"]&.strip
    return value unless value.nil? || value.empty?

    nil
  end

  def resolve_url_basename_time_file_size(url, timeout: nil)
    resolved_url, _, last_modified, file_size, content_type, is_redirection = super
    [resolved_url, @resolved_basename, last_modified, file_size, content_type, is_redirection]
  end

  def curl_output(*args, **options)
    super(*args, secrets: [@github_token], **options)
  end

  def curl(*args, print_stdout: true, **options)
    super(*args, print_stdout: print_stdout, secrets: [@github_token], **options)
  end
end

class Tabex < Formula
  desc "Tabex CLI for browser session, capture, and page inspection"
  homepage "https://github.com/shpitdev/tabex"
  version "0.0.5"
  license :cannot_represent
  depends_on arch: :arm64

  on_macos do
    on_arm do
      url "https://api.github.com/repos/shpitdev/tabex/releases/assets/401540246",
          using: TabexGitHubReleaseDownloadStrategy,
          resolved_basename: "tabex_v0.0.5_darwin_arm64.tar.gz"
      sha256 "e4a7477b220fbb31e21cf818e88be56e013dfbf3fe2b70bc862171287275e80f"
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

      That saves browser config, installs or updates the managed Chrome extension locally,
      and prints the Chrome load or refresh steps.
    EOS
  end

  test do
    require "json"

    payload = JSON.parse(shell_output("#{bin}/tabex --json"))
    assert_equal "tabex", payload["command"]
    assert_equal "tabex <command>", payload["usage"]
    assert_equal "v#{version}", payload["version"]
    assert_equal "docs/curated-e2e-examples.md", payload["curatedExamplesDoc"]
    assert_equal "setup", payload["examples"].first["label"]
  end
end
