class FoundryCliGitHubReleaseDownloadStrategy < CurlDownloadStrategy
  def initialize(url, name, version, **meta)
    @resolved_basename = meta.delete(:resolved_basename)
    @github_token = resolve_github_token

    if @github_token.nil? || @github_token.empty?
      raise CurlDownloadStrategyError.new(
        url,
        [
          "GitHub authentication is required to download the private foundry-cli release asset.",
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

class FoundryCli < Formula
  desc "Foundry DevOps automation CLI"
  homepage "https://github.com/shpitdev/foundry-cli"
  version "0.2.6"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/742126339",
          using: FoundryCliGitHubReleaseDownloadStrategy,
          resolved_basename: "foundry-cli_0.2.6_darwin_arm64.tar.gz"
      sha256 "d180cbd2fd30265e1682ed172de8d722fcee81a253de1fbcaaec2a9e79d676bb"
    end

    on_intel do
      url "https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/742126271",
          using: FoundryCliGitHubReleaseDownloadStrategy,
          resolved_basename: "foundry-cli_0.2.6_darwin_amd64.tar.gz"
      sha256 "90df9b5aaf3b7c9adc2b685ffa1327dd0056b81d7f6b91c1e45e7e4e62dc3782"
    end
  end

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"foundry-cli"
  end

  def caveats
    <<~EOS
      Package-manager installs do not edit your shell config.

      To add shell completion in zsh:
        printf '\nsource <(foundry-cli completion --code zsh)\n' >> ~/.zshrc

      To add it in bash:
        printf '\nsource <(foundry-cli completion --code bash)\n' >> ~/.bashrc
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/foundry-cli version")
  end
end
