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
fi

meshix_formula="${repo_root}/Formula/meshix-cli.rb"
if [[ -f "${meshix_formula}" ]]; then
  grep -q 'using: MeshixCliGitHubReleaseDownloadStrategy' "${meshix_formula}"
  grep -q 'resolved_basename: "meshix-cli_v' "${meshix_formula}"
  grep -q 'url "https://api.github.com/repos/shpitdev/meshix-mono/releases/assets/' "${meshix_formula}"
  grep -q 'depends_on "node@24"' "${meshix_formula}"
  grep -q 'bin.env_script_all_files(libexec, PATH: "#{Formula\["node@24"\].opt_bin}:\$PATH")' "${meshix_formula}"
  grep -q 'bin.install "meshix-cli"' "${meshix_formula}"
  grep -q 'meshix-cli --help' "${meshix_formula}"
  grep -q 'assert_equal "typescript", payload\["runtime"\]' "${meshix_formula}"
  grep -q 'meshix-cli-dev' "${meshix_formula}"
fi

foundry_formula="${repo_root}/Formula/foundry-cli.rb"
if [[ -f "${foundry_formula}" ]]; then
  expected_foundry_version="0.0.43"
  expected_foundry_arm64_asset_id="514107332"
  expected_foundry_arm64_basename="foundry-cli_0.0.43_darwin_arm64.tar.gz"
  expected_foundry_arm64_sha="c71b949e4a2da656cddddfdc526e12d47d6d1dcd5dbcfa840254a6bc6a966045"
  expected_foundry_amd64_asset_id="514107331"
  expected_foundry_amd64_basename="foundry-cli_0.0.43_darwin_amd64.tar.gz"
  expected_foundry_amd64_sha="02b9f8ba1400301e6409935dc3d48084e7ddb2da78cdbfaae10968ec45754240"

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
  if [[ -z "${MESHIX_CLI_VERSION:-}" && -f Formula/meshix-cli.rb ]]; then
    MESHIX_CLI_VERSION="$(sed -n 's/^  version "\([^"]*\)"$/\1/p' Formula/meshix-cli.rb | head -n 1)"
    export MESHIX_CLI_VERSION
  fi
  ./scripts/update-formulae.sh auto
)

diff -ru "${repo_root}/Formula" "${tmpdir}/repo/Formula"
diff -u "${repo_root}/scripts/validate-formulae.sh" "${tmpdir}/repo/scripts/validate-formulae.sh"

"${repo_root}/scripts/test-update-foundry-cli.sh"
"${repo_root}/scripts/test-update-tabex.sh"
