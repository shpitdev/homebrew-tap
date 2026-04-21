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
formula_path="${repo_root}/Formula/osyrra.rb"
repo="shpitdev/osyrra"

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

if [[ -n "${SHPIT_GH_TOKEN:-}" ]]; then
  release_json="$(GH_TOKEN="${SHPIT_GH_TOKEN}" gh api "repos/${repo}/releases/latest")"
elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping osyrra: SHPIT_GH_TOKEN is not configured in GitHub Actions." >&2
    exit 0
  fi
  echo "SHPIT_GH_TOKEN is required in GitHub Actions to read the private osyrra release." >&2
  exit 1
else
  release_json="$(gh api "repos/${repo}/releases/latest")"
fi

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
    echo "Skipping osyrra: latest release is missing a darwin arm64 archive." >&2
    exit 0
  fi
  echo "osyrra latest release is missing a darwin arm64 archive" >&2
  exit 1
fi

if [[ -z "${arm64_sha}" || "${arm64_sha}" == "null" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping osyrra: latest release is missing a darwin arm64 digest." >&2
    exit 0
  fi
  echo "osyrra latest release is missing a darwin arm64 digest" >&2
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
  tar -tzf "${arm64_asset}" | grep -qx "osyrra_v${version}_darwin_arm64/osyrra"
)

cat > "${formula_path}" <<EOF
class OsyrraGitHubReleaseDownloadStrategy < CurlDownloadStrategy
  def initialize(url, name, version, **meta)
    @resolved_basename = meta.delete(:resolved_basename)
    @github_token = resolve_github_token

    if @github_token.nil? || @github_token.empty?
      raise CurlDownloadStrategyError.new(
        url,
        [
          "GitHub authentication is required to download the private osyrra release asset.",
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

class Osyrra < Formula
  desc "Osyrra silent email worker and operator TUI"
  homepage "https://github.com/shpitdev/osyrra"
  version "${version}"
  license :cannot_represent
  depends_on arch: :arm64

  on_macos do
    on_arm do
      url "${arm64_api_url}",
          using: OsyrraGitHubReleaseDownloadStrategy,
          resolved_basename: "${arm64_asset}"
      sha256 "${arm64_sha}"
    end
  end

  def install
    bin.install "osyrra"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/osyrra version")
  end
end
EOF
