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
formula_path="${repo_root}/Formula/foundry-cli.rb"
validator_path="${repo_root}/scripts/validate-formulae.sh"
repo="shpitdev/foundry-cli"
asset_prefix="foundry-cli"
release_tag="${FOUNDRY_CLI_RELEASE_TAG:-}"

is_optional_discovery() {
  [[ "${optional}" == "true" && -z "${release_tag}" ]]
}

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

verify_release_archive() {
  local archive="$1"
  local listing

  listing="$(tar -tzf "${archive}")"

  grep -Fxq "foundry-cli" <<<"${listing}"
  grep -Fxq "LICENSE" <<<"${listing}"
  grep -Fxq "README.md" <<<"${listing}"
  grep -Fxq "templates/catalog.json" <<<"${listing}"

  if ! grep -Eq '^templates/(compute-module-ts|compute-modules/typescript)/package\.json$' <<<"${listing}"; then
    echo "Release archive ${archive} is missing a recognized compute module template package.json." >&2
    exit 1
  fi
}

fetch_release_by_tag() {
  local tag="$1"

  if [[ -n "${SHPIT_GH_TOKEN:-}" ]]; then
    GH_TOKEN="${SHPIT_GH_TOKEN}" gh api "repos/${repo}/releases/tags/${tag}"
  else
    gh api "repos/${repo}/releases/tags/${tag}"
  fi
}

fetch_release_with_assets() {
  local include_prereleases="$1"
  local releases_json

  if [[ -n "${SHPIT_GH_TOKEN:-}" ]]; then
    if ! releases_json="$(GH_TOKEN="${SHPIT_GH_TOKEN}" gh api --paginate "repos/${repo}/releases")"; then
      return 1
    fi
  else
    if ! releases_json="$(gh api --paginate "repos/${repo}/releases")"; then
      return 1
    fi
  fi

  jq -s -c --arg asset_prefix "${asset_prefix}" --argjson include_prereleases "${include_prereleases}" '
    add
    | map(select(.draft | not))
    | map(select($include_prereleases or (.prerelease | not)))
    | map(select(
        any(.assets[]?; (.name | test("^" + $asset_prefix + "_.*_darwin_amd64\\.tar\\.gz$"))) and
        any(.assets[]?; (.name | test("^" + $asset_prefix + "_.*_darwin_arm64\\.tar\\.gz$")))
      ))
    | first // empty
  ' <<<"${releases_json}"
}

skip_inaccessible_release() {
  if is_optional_discovery; then
    echo "Skipping foundry-cli: release metadata is not accessible in ${repo}." >&2
    exit 0
  fi
  echo "Unable to read foundry-cli release metadata in ${repo}." >&2
  exit 1
}

if [[ -n "${release_tag}" ]]; then
  release_json="$(fetch_release_by_tag "${release_tag}")" || skip_inaccessible_release
elif [[ -n "${SHPIT_GH_TOKEN:-}" || -z "${GITHUB_ACTIONS:-}" ]]; then
  release_json="$(fetch_release_with_assets false)" || skip_inaccessible_release
  if [[ -z "${release_json}" || "${release_json}" == "null" ]]; then
    release_json="$(fetch_release_with_assets true)" || skip_inaccessible_release
  fi
elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  if is_optional_discovery; then
    echo "Skipping foundry-cli: SHPIT_GH_TOKEN is not configured in GitHub Actions." >&2
    exit 0
  fi
  echo "SHPIT_GH_TOKEN is required in GitHub Actions to read the private foundry-cli release." >&2
  exit 1
fi

if [[ -z "${release_json}" || "${release_json}" == "null" ]]; then
  if is_optional_discovery; then
    echo "Skipping foundry-cli: no release contains foundry-cli darwin archives." >&2
    exit 0
  fi
  echo "foundry-cli has no release with darwin archives" >&2
  exit 1
fi

version="$(jq -r '.tag_name | ltrimstr("v")' <<<"${release_json}")"
amd64_json="$(jq -c --arg asset_prefix "${asset_prefix}" '
  .assets
  | map(select(.name | test("^" + $asset_prefix + "_.*_darwin_amd64\\.tar\\.gz$")))
  | first
' <<<"${release_json}")"
arm64_json="$(jq -c --arg asset_prefix "${asset_prefix}" '
  .assets
  | map(select(.name | test("^" + $asset_prefix + "_.*_darwin_arm64\\.tar\\.gz$")))
  | first
' <<<"${release_json}")"

amd64_asset="$(jq -r '.name // empty' <<<"${amd64_json}")"
amd64_api_url="$(jq -r '.url // empty' <<<"${amd64_json}")"
amd64_sha="$(jq -r '.digest // empty' <<<"${amd64_json}")"
arm64_asset="$(jq -r '.name // empty' <<<"${arm64_json}")"
arm64_api_url="$(jq -r '.url // empty' <<<"${arm64_json}")"
arm64_sha="$(jq -r '.digest // empty' <<<"${arm64_json}")"

if [[ -z "${amd64_asset}" || "${amd64_asset}" == "null" || -z "${amd64_api_url}" || "${amd64_api_url}" == "null" || -z "${arm64_asset}" || "${arm64_asset}" == "null" || -z "${arm64_api_url}" || "${arm64_api_url}" == "null" ]]; then
  if is_optional_discovery; then
    echo "Skipping foundry-cli: selected release is missing required darwin archives." >&2
    exit 0
  fi
  echo "foundry-cli selected release is missing required darwin archives" >&2
  exit 1
fi

if [[ -z "${amd64_sha}" || "${amd64_sha}" == "null" || -z "${arm64_sha}" || "${arm64_sha}" == "null" ]]; then
  if is_optional_discovery; then
    echo "Skipping foundry-cli: selected release is missing darwin asset digests." >&2
    exit 0
  fi
  echo "foundry-cli selected release is missing darwin asset digests" >&2
  exit 1
fi

amd64_sha="${amd64_sha#sha256:}"
arm64_sha="${arm64_sha#sha256:}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

if [[ -n "${SHPIT_GH_TOKEN:-}" ]]; then
  GH_TOKEN="${SHPIT_GH_TOKEN}" gh release download "v${version}" --repo "${repo}" \
    --pattern "${amd64_asset}" --pattern "${arm64_asset}" --dir "${tmpdir}" --clobber >/dev/null
else
  gh release download "v${version}" --repo "${repo}" \
    --pattern "${amd64_asset}" --pattern "${arm64_asset}" --dir "${tmpdir}" --clobber >/dev/null
fi

(
  cd "${tmpdir}"
  verify_sha256 "${amd64_sha}" "${amd64_asset}"
  verify_sha256 "${arm64_sha}" "${arm64_asset}"
  verify_release_archive "${amd64_asset}"
  verify_release_archive "${arm64_asset}"
)

cat > "${formula_path}" <<EOF
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
  version "${version}"
  license :cannot_represent

  on_macos do
    on_arm do
      url "${arm64_api_url}",
          using: FoundryCliGitHubReleaseDownloadStrategy,
          resolved_basename: "${arm64_asset}"
      sha256 "${arm64_sha}"
    end

    on_intel do
      url "${amd64_api_url}",
          using: FoundryCliGitHubReleaseDownloadStrategy,
          resolved_basename: "${amd64_asset}"
      sha256 "${amd64_sha}"
    end
  end

  def install
    libexec.install Dir["*"]

    templates_root = libexec/"templates"
    templates_root.mkpath

    template_readme = templates_root/"README.md"
    template_readme.write("# templates\n") unless template_readme.exist?

    bin.install_symlink libexec/"foundry-cli"
  end

  def caveats
    <<~EOS
      Package-manager installs do not edit your shell config.

      To add shell completion in zsh:
        printf '\\nsource <(foundry-cli completion --code zsh)\\n' >> ~/.zshrc

      To add it in bash:
        printf '\\nsource <(foundry-cli completion --code bash)\\n' >> ~/.bashrc
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/foundry-cli version")
  end
end
EOF

validator_tmp="${tmpdir}/validate-formulae.sh"
awk \
  -v version="${version}" \
  -v arm64_asset_id="${arm64_api_url##*/}" \
  -v arm64_basename="${arm64_asset}" \
  -v arm64_sha="${arm64_sha}" \
  -v amd64_asset_id="${amd64_api_url##*/}" \
  -v amd64_basename="${amd64_asset}" \
  -v amd64_sha="${amd64_sha}" '
  /^  expected_foundry_version=/ {
    print "  expected_foundry_version=\"" version "\""
    updated++
    next
  }
  /^  expected_foundry_arm64_asset_id=/ {
    print "  expected_foundry_arm64_asset_id=\"" arm64_asset_id "\""
    updated++
    next
  }
  /^  expected_foundry_arm64_basename=/ {
    print "  expected_foundry_arm64_basename=\"" arm64_basename "\""
    updated++
    next
  }
  /^  expected_foundry_arm64_sha=/ {
    print "  expected_foundry_arm64_sha=\"" arm64_sha "\""
    updated++
    next
  }
  /^  expected_foundry_amd64_asset_id=/ {
    print "  expected_foundry_amd64_asset_id=\"" amd64_asset_id "\""
    updated++
    next
  }
  /^  expected_foundry_amd64_basename=/ {
    print "  expected_foundry_amd64_basename=\"" amd64_basename "\""
    updated++
    next
  }
  /^  expected_foundry_amd64_sha=/ {
    print "  expected_foundry_amd64_sha=\"" amd64_sha "\""
    updated++
    next
  }
  { print }
  END {
    if (updated != 7) {
      print "Unable to update foundry-cli validator expectations." > "/dev/stderr"
      exit 1
    }
  }
' "${validator_path}" > "${validator_tmp}"
chmod +x "${validator_tmp}"
mv "${validator_tmp}" "${validator_path}"
