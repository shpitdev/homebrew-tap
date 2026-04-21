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

release_json="$(gh api "repos/${repo}/releases/latest")"
version="$(jq -r '.tag_name | ltrimstr("v")' <<<"${release_json}")"
arm64_json="$(jq -c '
  .assets
  | map(select(.name | test("_darwin_arm64\\.tar\\.gz$")))
  | first
' <<<"${release_json}")"

arm64_asset="$(jq -r '.name // empty' <<<"${arm64_json}")"
arm64_sha="$(jq -r '.digest // empty' <<<"${arm64_json}")"

if [[ -z "${arm64_asset}" || "${arm64_asset}" == "null" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping meshix-cli: latest release is missing a darwin arm64 archive." >&2
    exit 0
  fi
  echo "meshix-cli latest release is missing a darwin arm64 archive" >&2
  exit 1
fi

if [[ -z "${arm64_sha}" || "${arm64_sha}" == "null" ]]; then
  if [[ "${optional}" == "true" ]]; then
    echo "Skipping meshix-cli: latest release is missing a darwin arm64 digest." >&2
    exit 0
  fi
  echo "meshix-cli latest release is missing a darwin arm64 digest" >&2
  exit 1
fi

arm64_sha="${arm64_sha#sha256:}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

gh release download "v${version}" --repo "${repo}" \
  --pattern "${arm64_asset}" --dir "${tmpdir}" --clobber >/dev/null

(
  cd "${tmpdir}"
  verify_sha256 "${arm64_sha}" "${arm64_asset}"
  tar -tzf "${arm64_asset}" | grep -qx "meshix-cli_v${version}_darwin_arm64/meshix-cli"
)

cat > "${formula_path}" <<EOF
class MeshixCli < Formula
  desc "Meshix CLI for run inspection and generation workflows"
  homepage "https://github.com/shpitdev/meshix-observability"
  version "${version}"
  license :cannot_represent
  depends_on arch: :arm64

  on_macos do
    on_arm do
      url "https://github.com/shpitdev/meshix-observability/releases/download/v${version}/${arm64_asset}"
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
