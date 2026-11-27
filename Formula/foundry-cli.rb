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
  version "0.2.10"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/800909654",
          using: FoundryCliGitHubReleaseDownloadStrategy,
          resolved_basename: "foundry-cli_0.2.10_darwin_arm64.tar.gz"
      sha256 "aa81ff35002b47a6ed3022446fc4c427c0f926f42569614af701e16f5c66bc36"
    end

    on_intel do
      url "https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/800909546",
          using: FoundryCliGitHubReleaseDownloadStrategy,
          resolved_basename: "foundry-cli_0.2.10_darwin_amd64.tar.gz"
      sha256 "a255697d60f4f567401356bee7ef03306c33df5f04a72f197354cb82cab9f409"
    end
  end

  def install
    libexec.install Dir["*"]
    go = libexec/"bin/foundry-cli-go"
    FileUtils.mv libexec/"foundry-cli", go
    bin.install_symlink go, libexec/"bin/foundry-cli-ts"
    bin.install_symlink go => "foundry-cli"
    bin.install_symlink go => "fcli"
  end

  def caveats
    <<~EOS
      Package-manager installs do not edit your shell config.
      foundry-cli and fcli run Go. Use install.sh --alias ts for a standalone install with TypeScript as the default.
      foundry-cli-ts and foundry-cli superrepo need Node.js 24.15 or later on PATH.

      To add shell completion in zsh:
        printf '\nsource <(foundry-cli completion --code zsh)\n' >> ~/.zshrc

      To add it in bash:
        printf '\nsource <(foundry-cli completion --code bash)\n' >> ~/.bashrc
    EOS
  end

  test do
    %w[foundry-cli-go foundry-cli fcli].each do |name|
      assert_match version.to_s, shell_output("#{bin}/#{name} version")
    end

    # Node is optional; test the TypeScript executable only when it is on PATH.
    if which("node")
      assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/foundry-cli-ts version"))
    end
  end
end
