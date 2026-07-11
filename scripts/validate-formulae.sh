#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for formula in "${repo_root}"/Formula/*.rb; do
  [[ -f "${formula}" ]] || continue
  ruby -c "${formula}" >/dev/null
done

tabex_formula="${repo_root}/Formula/tabex.rb"
if [[ -f "${tabex_formula}" ]]; then
  grep -q 'using: TabexGitHubReleaseDownloadStrategy' "${tabex_formula}"
  grep -q 'resolved_basename: "tabex_v' "${tabex_formula}"
  grep -q 'url "https://api.github.com/repos/shpitdev/tabex/releases/assets/' "${tabex_formula}"
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
  grep -q 'bin.install "meshix-cli"' "${meshix_formula}"
  grep -q 'meshix-cli --help' "${meshix_formula}"
  grep -q 'meshix-cli-dev' "${meshix_formula}"
fi

foundry_formula="${repo_root}/Formula/foundry-cli.rb"
if [[ -f "${foundry_formula}" ]]; then
  grep -q 'class FoundryCli < Formula' "${foundry_formula}"
  grep -q 'using: FoundryCliGitHubReleaseDownloadStrategy' "${foundry_formula}"
  grep -q 'resolved_basename: "foundry-cli_' "${foundry_formula}"
  grep -q 'url "https://api.github.com/repos/shpitdev/foundry-cli/releases/assets/' "${foundry_formula}"
  grep -q 'bin.install_symlink libexec/"foundry-cli"' "${foundry_formula}"
  grep -q 'shell_output("#{bin}/foundry-cli version")' "${foundry_formula}"
  grep -q 'version "0.0.30"' "${foundry_formula}"
  grep -q 'releases/assets/468862204' "${foundry_formula}"
  grep -q 'sha256 "1707fba1d52a7203d442ed21d751535535bd706c85c367f8fffc93399a7f9181"' "${foundry_formula}"
  grep -q 'releases/assets/468862181' "${foundry_formula}"
  grep -q 'sha256 "7a960f0d58f1d5da2d61f4bde0725d443bcbaa15b7b659b8c3b0d3fdbfcbbda1"' "${foundry_formula}"
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

"${repo_root}/scripts/test-update-foundry-cli.sh"
