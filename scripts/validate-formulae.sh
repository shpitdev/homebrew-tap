#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for formula in "${repo_root}"/Formula/*.rb; do
  [[ -f "${formula}" ]] || continue
  ruby -c "${formula}" >/dev/null
done

tabex_formula="${repo_root}/Formula/tabex.rb"
if [[ -f "${tabex_formula}" ]]; then
  grep -q 'shell_output("#{bin}/tabex --json")' "${tabex_formula}"
  grep -q 'assert_equal "v#{version}", payload\["version"\]' "${tabex_formula}"
  grep -q 'assert_equal "setup", payload\["startHere"\].first\["command"\]' "${tabex_formula}"
  grep -q 'Tabex needs browser-profile and extension setup after install.' "${tabex_formula}"
  grep -q 'tabex setup' "${tabex_formula}"
  grep -q 'Install Tabex from the Chrome Web Store' "${tabex_formula}"
  grep -q 'tabex browser native-host install' "${tabex_formula}"
  grep -q 'tabex browser native-host status' "${tabex_formula}"
fi

foundry_formula="${repo_root}/Formula/foundry-cli.rb"
if [[ -f "${foundry_formula}" ]]; then
  expected_foundry_version="0.0.70"
  expected_foundry_arm64_asset_id="670507704"
  expected_foundry_arm64_basename="foundry-cli_0.0.70_darwin_arm64.tar.gz"
  expected_foundry_arm64_sha="0e369dd8d366039aeb0ba5cff4e87504f59e7778512a66484ce4650b2327dabb"
  expected_foundry_amd64_asset_id="670507702"
  expected_foundry_amd64_basename="foundry-cli_0.0.70_darwin_amd64.tar.gz"
  expected_foundry_amd64_sha="90251225a191b3e261cb462f9dd94648a8a8fb3f91a49ff2f3f07c3821f2da99"

  grep -q 'class FoundryCli < Formula' "${foundry_formula}"
  grep -q 'using: FoundryCliGitHubReleaseDownloadStrategy' "${foundry_formula}"
  grep -q 'resolved_basename: "foundry-cli_' "${foundry_formula}"
  grep -q 'url "https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/' "${foundry_formula}"
  grep -q 'bin.install_symlink libexec/"foundry-cli"' "${foundry_formula}"
  grep -q 'shell_output("#{bin}/foundry-cli version")' "${foundry_formula}"
  grep -Fq "version \"${expected_foundry_version}\"" "${foundry_formula}"
  grep -Fq "releases/assets/${expected_foundry_arm64_asset_id}" "${foundry_formula}"
  grep -Fq "resolved_basename: \"${expected_foundry_arm64_basename}\"" "${foundry_formula}"
  grep -Fq "sha256 \"${expected_foundry_arm64_sha}\"" "${foundry_formula}"
  grep -Fq "releases/assets/${expected_foundry_amd64_asset_id}" "${foundry_formula}"
  grep -Fq "resolved_basename: \"${expected_foundry_amd64_basename}\"" "${foundry_formula}"
  grep -Fq "sha256 \"${expected_foundry_amd64_sha}\"" "${foundry_formula}"
  grep -q 'license :cannot_represent' "${foundry_formula}"
fi

osyrra_formula="${repo_root}/Formula/osyrra.rb"
if [[ -f "${osyrra_formula}" ]]; then
  grep -q 'using: OsyrraGitHubReleaseDownloadStrategy' "${osyrra_formula}"
  grep -q 'resolved_basename: "osyrra_v' "${osyrra_formula}"
  grep -q 'url "https://api.github.com/repos/shpitdev/osyrra/releases/assets/' "${osyrra_formula}"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

cp -a "${repo_root}/." "${tmpdir}/repo"
(
  cd "${tmpdir}/repo"
  ./scripts/update-formulae.sh auto
  FOUNDRY_CLI_RELEASE_TAG="v${expected_foundry_version}" ./scripts/update-foundry-cli.sh --optional
)

diff -ru "${repo_root}/Formula" "${tmpdir}/repo/Formula"
diff -u "${repo_root}/scripts/validate-formulae.sh" "${tmpdir}/repo/scripts/validate-formulae.sh"

"${repo_root}/scripts/test-update-foundry-cli.sh"
"${repo_root}/scripts/test-update-tabex.sh"

"${repo_root}/scripts/bump-foundry-cli-release.test.sh"
