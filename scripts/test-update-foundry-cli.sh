#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

mkdir -p "${test_root}/repo/Formula" "${test_root}/repo/scripts" "${test_root}/bin" "${test_root}/archives"
cp "${repo_root}/Formula/foundry-cli.rb" "${test_root}/repo/Formula/foundry-cli.rb"
cp "${repo_root}/scripts/update-foundry-cli.sh" "${test_root}/repo/scripts/update-foundry-cli.sh"
cp "${repo_root}/scripts/validate-formulae.sh" "${test_root}/repo/scripts/validate-formulae.sh"

cat > "${test_root}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "api" ]]; then
  if [[ "${MOCK_API_FAIL:-false}" == "true" ]]; then
    echo "mock release metadata failure" >&2
    exit 1
  fi
  printf '%s\n' "${MOCK_RELEASE_JSON:?}"
  exit 0
fi

if [[ "$1" == "release" && "$2" == "download" ]]; then
  shift 2
  patterns=()
  destination=""
  while (($#)); do
    case "$1" in
      --pattern)
        patterns+=("$2")
        shift 2
        ;;
      --dir)
        destination="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  for pattern in "${patterns[@]}"; do
    cp "${MOCK_ARCHIVE_DIR:?}/${pattern}" "${destination}/${pattern}"
  done
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "${test_root}/bin/gh"

updater="${test_root}/repo/scripts/update-foundry-cli.sh"
common_env=(
  PATH="${test_root}/bin:${PATH}"
  GITHUB_ACTIONS=true
  SHPIT_GH_TOKEN=test-token
)

assert_fails() {
  local message="$1"
  shift
  if "$@" >"${test_root}/stdout" 2>"${test_root}/stderr"; then
    echo "Expected failure: ${message}" >&2
    exit 1
  fi
}

assert_succeeds() {
  local message="$1"
  shift
  if ! "$@" >"${test_root}/stdout" 2>"${test_root}/stderr"; then
    echo "Expected success: ${message}" >&2
    cat "${test_root}/stderr" >&2
    exit 1
  fi
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

assert_fails "an explicit missing tag must not be hidden by --optional" \
  env "${common_env[@]}" MOCK_API_FAIL=true FOUNDRY_CLI_RELEASE_TAG=v-does-not-exist \
  "${updater}" --optional
grep -Fq "Unable to read foundry-cli release metadata" "${test_root}/stderr"

assert_succeeds "unpinned optional discovery may skip inaccessible metadata" \
  env "${common_env[@]}" MOCK_API_FAIL=true FOUNDRY_CLI_RELEASE_TAG= \
  "${updater}" --optional
grep -Fq "Skipping foundry-cli: release metadata is not accessible" "${test_root}/stderr"

make_archive() {
  local output="$1"
  local include_catalog="$2"
  local root="${test_root}/archive-root"

  rm -rf "${root}"
  mkdir -p "${root}/templates/compute-module-ts"
  touch "${root}/foundry-cli"
  printf 'proprietary\n' > "${root}/LICENSE"
  printf '# foundry-cli\n' > "${root}/README.md"
  printf '{}\n' > "${root}/templates/compute-module-ts/package.json"
  if [[ "${include_catalog}" == "true" ]]; then
    printf '{}\n' > "${root}/templates/catalog.json"
  fi
  (
    cd "${root}"
    tar -czf "${output}" foundry-cli LICENSE README.md templates
  )
}

version="9.9.9"
amd64_asset="foundry-cli_${version}_darwin_amd64.tar.gz"
arm64_asset="foundry-cli_${version}_darwin_arm64.tar.gz"
make_archive "${test_root}/archives/${amd64_asset}" false
make_archive "${test_root}/archives/${arm64_asset}" false

amd64_sha="$(sha256_file "${test_root}/archives/${amd64_asset}")"
arm64_sha="$(sha256_file "${test_root}/archives/${arm64_asset}")"
release_json="$(jq -nc \
  --arg version "v${version}" \
  --arg amd64_asset "${amd64_asset}" \
  --arg arm64_asset "${arm64_asset}" \
  --arg amd64_sha "sha256:${amd64_sha}" \
  --arg arm64_sha "sha256:${arm64_sha}" \
  '{tag_name:$version,assets:[
    {name:$amd64_asset,url:"https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/101",digest:$amd64_sha},
    {name:$arm64_asset,url:"https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/102",digest:$arm64_sha}
  ]}')"

assert_fails "archives without templates/catalog.json must be rejected" \
  env "${common_env[@]}" MOCK_API_FAIL=false MOCK_RELEASE_JSON="${release_json}" \
  MOCK_ARCHIVE_DIR="${test_root}/archives" FOUNDRY_CLI_RELEASE_TAG="v${version}" \
  "${updater}" --optional

make_archive "${test_root}/archives/${amd64_asset}" true
make_archive "${test_root}/archives/${arm64_asset}" true
amd64_sha="$(sha256_file "${test_root}/archives/${amd64_asset}")"
arm64_sha="$(sha256_file "${test_root}/archives/${arm64_asset}")"
release_json="$(jq -nc \
  --arg version "v${version}" \
  --arg amd64_asset "${amd64_asset}" \
  --arg arm64_asset "${arm64_asset}" \
  --arg amd64_sha "sha256:${amd64_sha}" \
  --arg arm64_sha "sha256:${arm64_sha}" \
  '{tag_name:$version,assets:[
    {name:$amd64_asset,url:"https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/101",digest:$amd64_sha},
    {name:$arm64_asset,url:"https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/102",digest:$arm64_sha}
  ]}')"

assert_succeeds "a complete release generates a proprietary formula" \
  env "${common_env[@]}" MOCK_API_FAIL=false MOCK_RELEASE_JSON="${release_json}" \
  MOCK_ARCHIVE_DIR="${test_root}/archives" FOUNDRY_CLI_RELEASE_TAG="v${version}" \
  "${updater}" --optional

generated_formula="${test_root}/repo/Formula/foundry-cli.rb"
grep -Fq 'version "9.9.9"' "${generated_formula}"
grep -Fq 'license :cannot_represent' "${generated_formula}"
grep -Fq 'releases/assets/101' "${generated_formula}"
grep -Fq "sha256 \"${amd64_sha}\"" "${generated_formula}"
grep -Fq 'releases/assets/102' "${generated_formula}"
grep -Fq "sha256 \"${arm64_sha}\"" "${generated_formula}"

generated_validator="${test_root}/repo/scripts/validate-formulae.sh"
grep -Fq 'expected_foundry_version="9.9.9"' "${generated_validator}"
grep -Fq 'expected_foundry_arm64_asset_id="102"' "${generated_validator}"
grep -Fq "expected_foundry_arm64_basename=\"${arm64_asset}\"" "${generated_validator}"
grep -Fq "expected_foundry_arm64_sha=\"${arm64_sha}\"" "${generated_validator}"
grep -Fq 'expected_foundry_amd64_asset_id="101"' "${generated_validator}"
grep -Fq "expected_foundry_amd64_basename=\"${amd64_asset}\"" "${generated_validator}"
grep -Fq "expected_foundry_amd64_sha=\"${amd64_sha}\"" "${generated_validator}"

seed_formula="${repo_root}/Formula/foundry-cli.rb"
grep -Fq 'version "0.0.31"' "${seed_formula}"
grep -Fq 'releases/assets/476012067' "${seed_formula}"
grep -Fq 'sha256 "b7ccc08293d098a5ec6ddbe581099ad27610540e0593224a5bc4462fca3aaeb7"' "${seed_formula}"
grep -Fq 'releases/assets/476012073' "${seed_formula}"
grep -Fq 'sha256 "0f5bead326e530c1379ae39f27c765a12b1f801a1d006c1e3e0515fe8460e5f2"' "${seed_formula}"
grep -Fq 'license :cannot_represent' "${seed_formula}"
