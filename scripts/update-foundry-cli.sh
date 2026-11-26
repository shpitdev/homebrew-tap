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

  local required
  for required in '^foundry-cli$' '^LICENSE$' '^README\.md$' '^bin/foundry-cli-ts$' \
    '^libexec/cli-ts/[^/]+/launch\.cjs$' '^libexec/superrepo/[^/]+/main\.mjs$'; do
    if ! grep -Eq "${required}" <<<"${listing}"; then
      echo "Release archive ${archive} is missing a required member (${required})." >&2
      return 1
    fi
  done
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

# Keep the recipe and its authenticated download strategy in the formula, not a second template.
formula_tmp="${tmpdir}/foundry-cli.rb"
awk \
  -v version="${version}" \
  -v arm64_url="${arm64_api_url}" -v arm64_asset="${arm64_asset}" -v arm64_sha="${arm64_sha}" \
  -v amd64_url="${amd64_api_url}" -v amd64_asset="${amd64_asset}" -v amd64_sha="${amd64_sha}" '
  /^  version "/ {
    new_release = ($2 != "\"" version "\"")
    print "  version \"" version "\""
    updated++
    next
  }
  /^  revision [0-9]+$/ && new_release { next }
  /^    on_arm do$/   { url = arm64_url; asset = arm64_asset; sha = arm64_sha }
  /^    on_intel do$/ { url = amd64_url; asset = amd64_asset; sha = amd64_sha }
  /^    end$/ { url = "" }
  url && /^      url "/ {
    print "      url \"" url "\","
    updated++
    next
  }
  url && /^          resolved_basename: "/ {
    print "          resolved_basename: \"" asset "\""
    updated++
    next
  }
  url && /^      sha256 "/ {
    print "      sha256 \"" sha "\""
    updated++
    next
  }
  { print }
  END {
    if (updated != 7) {
      print "Unable to update foundry-cli formula metadata." > "/dev/stderr"
      exit 1
    }
  }
' "${formula_path}" > "${formula_tmp}"

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
mv "${formula_tmp}" "${formula_path}"
mv "${validator_tmp}" "${validator_path}"
