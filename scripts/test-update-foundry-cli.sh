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

seed_formula="${repo_root}/Formula/foundry-cli.rb"
seed_formula_sha_before="$(sha256_file "${seed_formula}")"

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
  local layout="$2"
  local omitted="${3:-}"
  local root="${test_root}/archive-root"
  local members=(foundry-cli LICENSE README.md)

  rm -rf "${root}"
  mkdir -p "${root}"
  printf '#!/bin/sh\n[ "$1" = version ] || exit 1\nprintf "foundry-cli fixture\\n"\n' > "${root}/foundry-cli"
  chmod +x "${root}/foundry-cli"
  printf 'proprietary\n' > "${root}/LICENSE"
  printf '# foundry-cli\n' > "${root}/README.md"
  case "${layout}" in
    core-only) ;;
    legacy-flat|legacy-nested)
      local template_dir="compute-module-ts"
      if [[ "${layout}" == "legacy-nested" ]]; then
        template_dir="compute-modules/typescript"
      fi
      mkdir -p "${root}/templates/${template_dir}"
      printf '{"templates":["%s"]}\n' "${template_dir}" > "${root}/templates/catalog.json"
      printf '{"name":"fixture-template"}\n' > "${root}/templates/${template_dir}/package.json"
      members+=(templates)
      ;;
    *) echo "Unknown archive layout: ${layout}" >&2; exit 1 ;;
  esac
  if [[ -n "${omitted}" ]]; then
    rm "${root}/${omitted}"
    members=()
    for member in foundry-cli LICENSE README.md; do
      [[ "${member}" == "${omitted}" ]] || members+=("${member}")
    done
  fi
  (
    cd "${root}"
    tar -czf "${output}" "${members[@]}"
  )
}

version="9.9.9"
amd64_asset="foundry-cli_${version}_darwin_amd64.tar.gz"
arm64_asset="foundry-cli_${version}_darwin_arm64.tar.gz"
generated_formula="${test_root}/repo/Formula/foundry-cli.rb"
generated_validator="${test_root}/repo/scripts/validate-formulae.sh"

set_release_json() {
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
}

run_updater() {
  env "${common_env[@]}" MOCK_API_FAIL=false MOCK_RELEASE_JSON="${release_json}" \
    MOCK_ARCHIVE_DIR="${test_root}/archives" FOUNDRY_CLI_RELEASE_TAG="v${version}" \
    "${updater}" --optional
}

assert_rejected_without_writes() {
  local message="$1"
  local formula_before validator_before
  formula_before="$(sha256_file "${generated_formula}")"
  validator_before="$(sha256_file "${generated_validator}")"
  assert_fails "${message}" run_updater
  [[ "$(sha256_file "${generated_formula}")" == "${formula_before}" ]]
  [[ "$(sha256_file "${generated_validator}")" == "${validator_before}" ]]
  echo "Passed: ${message} (no formula or validator writes)"
}

assert_install() {
  local formula="$1"
  local archive="$2"
  local stage="${test_root}/install-stage"
  local prefix="${test_root}/install-prefix"
  rm -rf "${stage}" "${prefix}"
  mkdir -p "${stage}"
  tar -xzf "${archive}" -C "${stage}"
  ruby "${repo_root}/scripts/test-install-foundry-cli.rb" "${formula}" "${stage}" "${prefix}"
}

for layout in core-only legacy-flat legacy-nested; do
  make_archive "${test_root}/archives/${amd64_asset}" "${layout}"
  make_archive "${test_root}/archives/${arm64_asset}" "${layout}"
  set_release_json
  assert_succeeds "${layout} archives generate a formula" run_updater
  # Execute both the checked-in and generated install methods, not source snapshots.
  assert_install "${seed_formula}" "${test_root}/archives/${arm64_asset}"
  assert_install "${generated_formula}" "${test_root}/archives/${arm64_asset}"
  echo "Passed: ${layout} updater and install-method harness (seed + generated)"
done

# Asset validation must not depend on the two architectures sharing a layout.
for layout in legacy-flat core-only; do
  make_archive "${test_root}/archives/${amd64_asset}" "${layout}"
  if [[ "${layout}" == "core-only" ]]; then
    make_archive "${test_root}/archives/${arm64_asset}" legacy-nested
  else
    make_archive "${test_root}/archives/${arm64_asset}" core-only
  fi
  set_release_json
  assert_succeeds "mixed core/legacy archives generate a formula" run_updater
  echo "Passed: mixed layouts with ${layout} amd64"
done

grep -Fq 'version "9.9.9"' "${generated_formula}"
grep -Fq 'license :cannot_represent' "${generated_formula}"
grep -Fq 'releases/assets/101' "${generated_formula}"
grep -Fq "sha256 \"${amd64_sha}\"" "${generated_formula}"
grep -Fq 'releases/assets/102' "${generated_formula}"
grep -Fq "sha256 \"${arm64_sha}\"" "${generated_formula}"

grep -Fq 'expected_foundry_version="9.9.9"' "${generated_validator}"
grep -Fq 'expected_foundry_arm64_asset_id="102"' "${generated_validator}"
grep -Fq "expected_foundry_arm64_basename=\"${arm64_asset}\"" "${generated_validator}"
grep -Fq "expected_foundry_arm64_sha=\"${arm64_sha}\"" "${generated_validator}"
grep -Fq 'expected_foundry_amd64_asset_id="101"' "${generated_validator}"
grep -Fq "expected_foundry_amd64_basename=\"${amd64_asset}\"" "${generated_validator}"
grep -Fq "expected_foundry_amd64_sha=\"${amd64_sha}\"" "${generated_validator}"

for asset in "${amd64_asset}" "${arm64_asset}"; do
  for required_file in foundry-cli LICENSE README.md; do
    make_archive "${test_root}/archives/${amd64_asset}" core-only
    make_archive "${test_root}/archives/${arm64_asset}" core-only
    make_archive "${test_root}/archives/${asset}" core-only "${required_file}"
    set_release_json
    assert_rejected_without_writes "${asset} missing ${required_file} is rejected"
  done

  make_archive "${test_root}/archives/${amd64_asset}" core-only
  make_archive "${test_root}/archives/${arm64_asset}" core-only
  set_release_json
  printf 'tampered\n' >> "${test_root}/archives/${asset}"
  assert_rejected_without_writes "${asset} digest mismatch is rejected"
  grep -Fq 'SHA-256 mismatch' "${test_root}/stderr"

  printf 'not a tar archive\n' > "${test_root}/archives/${asset}"
  set_release_json
  assert_rejected_without_writes "${asset} malformed archive with matching digest is rejected"
done

seed_formula_sha_after="$(sha256_file "${seed_formula}")"
if [[ "${seed_formula_sha_after}" != "${seed_formula_sha_before}" ]]; then
  echo "The updater regression test modified the checked-out seed formula" >&2
  exit 1
fi
grep -Fq 'license :cannot_represent' "${seed_formula}"
echo "Passed: checked-out seed formula remains unchanged"
