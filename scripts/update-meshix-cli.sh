#!/usr/bin/env bash
set -euo pipefail

optional=false
if (($# > 1)); then
  echo "usage: $0 [--optional]" >&2
  exit 1
fi
if (($# == 1)); then
  if [[ "$1" != "--optional" ]]; then
    echo "usage: $0 [--optional]" >&2
    exit 1
  fi
  optional=true
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
formula_path="${repo_root}/Formula/meshix-cli.rb"
repo="shpitdev/meshix-observability"
requested_version="${MESHIX_CLI_VERSION:-latest}"

verify_sha256() {
  local expected="$1"
  local file="$2"
  local actual

  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${file}" | awk '{print $1}')"
  else
    echo "Unable to verify SHA-256: neither shasum nor sha256sum is available." >&2
    exit 1
  fi

  if [[ "${actual}" != "${expected}" ]]; then
    echo "SHA-256 mismatch for ${file}: expected ${expected}, got ${actual}." >&2
    exit 1
  fi
}

resolve_release_json() {
  local version="$1"
  local endpoint
  local output=""

  if [[ -z "${version}" || "${version}" == "latest" ]]; then
    endpoint="repos/${repo}/releases/latest"
  else
    if [[ "${version}" != v* ]]; then
      version="v${version}"
    fi
    endpoint="repos/${repo}/releases/tags/${version}"
  fi

  if [[ -n "${SHPIT_GH_TOKEN:-}" ]]; then
    if output="$(GH_TOKEN="${SHPIT_GH_TOKEN}" gh api "${endpoint}" 2>/dev/null)"; then
      printf '%s' "${output}"
      return 0
    fi
    if [[ -n "${GITHUB_ACTIONS:-}" && "${optional}" == "true" ]]; then
      echo "Skipping meshix-cli: SHPIT_GH_TOKEN does not currently grant release access to ${repo}." >&2
      exit 0
    fi
    echo "SHPIT_GH_TOKEN could not read the private meshix-cli release in ${repo}." >&2
    exit 1
  elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    if [[ "${optional}" == "true" ]]; then
      echo "Skipping meshix-cli: SHPIT_GH_TOKEN is not configured in GitHub Actions." >&2
      exit 0
    fi
    echo "SHPIT_GH_TOKEN is required in GitHub Actions to read the private meshix-cli release." >&2
    exit 1
  else
    gh api "${endpoint}"
  fi
}

release_json="$(resolve_release_json "${requested_version}")"
version="$(jq -r '.tag_name | ltrimstr("v")' <<<"${release_json}")"
arm64_json="$(jq -c '
  .assets
  | map(select(.name | test("_darwin_arm64\\.tar\\.gz$")))
  | first
' <<<"${release_json}")"

arm64_asset="$(jq -r '.name // empty' <<<"${arm64_json}")"
arm64_api_url="$(jq -r '.url // empty' <<<"${arm64_json}")"
arm64_sha="$(jq -r '.digest // empty' <<<"${arm64_json}")"

if [[ -z "${arm64_asset}" || "${arm64_asset}" == "null" || -z "${arm64_api_url}" || "${arm64_api_url}" == "null" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping meshix-cli: release is missing a darwin arm64 archive." >&2
    exit 0
  fi
  echo "meshix-cli release is missing a darwin arm64 archive" >&2
  exit 1
fi

if [[ -z "${arm64_sha}" || "${arm64_sha}" == "null" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping meshix-cli: release is missing a darwin arm64 digest." >&2
    exit 0
  fi
  echo "meshix-cli release is missing a darwin arm64 digest" >&2
  exit 1
fi

arm64_sha="${arm64_sha#sha256:}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

if [[ -n "${SHPIT_GH_TOKEN:-}" ]]; then
  GH_TOKEN="${SHPIT_GH_TOKEN}" gh release download "v${version}" --repo "${repo}" \
    --pattern "${arm64_asset}" --dir "${tmpdir}" --clobber >/dev/null
else
  gh release download "v${version}" --repo "${repo}" \
    --pattern "${arm64_asset}" --dir "${tmpdir}" --clobber >/dev/null
fi

(
  cd "${tmpdir}"
  verify_sha256 "${arm64_sha}" "${arm64_asset}"
  tar -tzf "${arm64_asset}" | grep -qx "meshix-cli_v${version}_darwin_arm64/meshix-cli"
)

cat > "${formula_path}" <<EOF
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
  version "${version}"
  license :cannot_represent
  depends_on arch: :arm64

  on_macos do
    on_arm do
      url "${arm64_api_url}",
          using: MeshixCliGitHubReleaseDownloadStrategy,
          resolved_basename: "${arm64_asset}"
      sha256 "${arm64_sha}"
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
EOF
