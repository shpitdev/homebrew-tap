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
formula_path="${repo_root}/Formula/tabex.rb"
repo="shpitdev/pkgbuilds"

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

releases_json="$(gh api --paginate "repos/${repo}/releases?per_page=100" --slurp)"
release_json="$(jq -c '
  [
    .[][]
    | select(.draft == false and .prerelease == false)
    | select(.tag_name | test("^tabex-v[0-9]+\\.[0-9]+\\.[0-9]+$"))
  ]
  | sort_by(.tag_name | sub("^tabex-v"; "") | split(".") | map(tonumber))
  | last // empty
' <<<"${releases_json}")"

if [[ -z "${release_json}" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping tabex: no public stable Tabex binary release exists yet." >&2
    exit 0
  fi
  echo "No public stable Tabex binary release exists in ${repo}." >&2
  exit 1
fi

public_tag="$(jq -r '.tag_name' <<<"${release_json}")"
version="${public_tag#tabex-v}"
arm64_json="$(jq -c '
  .assets
  | map(select(.name == "tabex_v'"${version}"'_darwin_arm64.tar.gz"))
  | first
' <<<"${release_json}")"

arm64_asset="$(jq -r '.name // empty' <<<"${arm64_json}")"
arm64_download_url="$(jq -r '.browser_download_url // empty' <<<"${arm64_json}")"
arm64_sha="$(jq -r '.digest // empty' <<<"${arm64_json}")"

if [[ -z "${arm64_asset}" || "${arm64_asset}" == "null" || -z "${arm64_download_url}" || "${arm64_download_url}" == "null" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping tabex: latest release is missing a darwin arm64 archive." >&2
    exit 0
  fi
  echo "tabex latest release is missing a darwin arm64 archive" >&2
  exit 1
fi

if [[ -z "${arm64_sha}" || "${arm64_sha}" == "null" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping tabex: latest release is missing a darwin arm64 digest." >&2
    exit 0
  fi
  echo "tabex latest release is missing a darwin arm64 digest" >&2
  exit 1
fi

arm64_sha="${arm64_sha#sha256:}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl --fail --location --silent --show-error \
  --output "${tmpdir}/${arm64_asset}" \
  "${arm64_download_url}"

(
  cd "${tmpdir}"
  verify_sha256 "${arm64_sha}" "${arm64_asset}"
  tar -tzf "${arm64_asset}" | grep -qx "tabex_v${version}_darwin_arm64/tabex"
)

cat > "${formula_path}" <<EOF
class Tabex < Formula
  desc "Tabex CLI for browser session, capture, and page inspection"
  homepage "https://github.com/shpitdev/tabex"
  version "${version}"
  license :cannot_represent
  depends_on arch: :arm64

  on_macos do
    on_arm do
      url "${arm64_download_url}"
      sha256 "${arm64_sha}"
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
    assert_equal "setup", payload["startHere"].first["command"]
  end
end
EOF
