class MeshixCliGitHubReleaseDownloadStrategy < CurlDownloadStrategy
  def initialize(url, name, version, **meta)
    @resolved_basename = meta.delete(:resolved_basename)
    @github_token = resolve_github_token

    if @github_token.nil? || @github_token.empty?
      raise CurlDownloadStrategyError.new(
        url,
        [
          "GitHub authentication is required to download the private meshix-cli release asset.",
          "Set HOMEBREW_GITHUB_API_TOKEN, GH_TOKEN, GITHUB_TOKEN, or SHPIT_GH_TOKEN,",
          "or log in with gh auth login."
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
    %w[HOMEBREW_GITHUB_API_TOKEN GH_TOKEN GITHUB_TOKEN SHPIT_GH_TOKEN].each do |key|
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

class MeshixCli < Formula
  desc "Meshix CLI for run inspection and generation workflows"
  homepage "https://github.com/shpitdev/meshix-observability"
  version "0.0.1"
  license :cannot_represent
  depends_on arch: :arm64

  on_macos do
    on_arm do
      url "https://api.github.com/repos/shpitdev/meshix-observability/releases/assets/391763692",
          using: MeshixCliGitHubReleaseDownloadStrategy,
          resolved_basename: "meshix-cli_v0.0.1_darwin_arm64.tar.gz"
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
