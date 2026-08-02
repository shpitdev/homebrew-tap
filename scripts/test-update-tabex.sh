#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

cp -a "${repo_root}/." "${workdir}/repo"
mkdir -p "${workdir}/bin" "${workdir}/stage/tabex_v9.8.7_darwin_arm64"
printf '#!/usr/bin/env bash\n' > "${workdir}/stage/tabex_v9.8.7_darwin_arm64/tabex"
tar -czf "${workdir}/tabex_v9.8.7_darwin_arm64.tar.gz" \
  -C "${workdir}/stage" tabex_v9.8.7_darwin_arm64
archive_sha="$(shasum -a 256 "${workdir}/tabex_v9.8.7_darwin_arm64.tar.gz" | awk '{print $1}')"

jq -n --arg sha "${archive_sha}" '[
  [
    {
      tag_name: "tabex-v9.8.6",
      draft: false,
      prerelease: false,
      assets: []
    },
    {
      tag_name: "tabex-v9.8.7",
      draft: false,
      prerelease: false,
      assets: [
        {
          name: "tabex_v9.8.7_darwin_arm64.tar.gz",
          browser_download_url: "https://github.com/shpitdev/pkgbuilds/releases/download/tabex-v9.8.7/tabex_v9.8.7_darwin_arm64.tar.gz",
          digest: ("sha256:" + $sha)
        }
      ]
    }
  ]
]' > "${workdir}/release.json"

cat > "${workdir}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat "${TABEX_RELEASE_FIXTURE}"
EOF

cat > "${workdir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cp "${TABEX_ARCHIVE_FIXTURE}" "${output}"
EOF

chmod +x "${workdir}/bin/gh" "${workdir}/bin/curl"

PATH="${workdir}/bin:${PATH}" \
  TABEX_RELEASE_FIXTURE="${workdir}/release.json" \
  TABEX_ARCHIVE_FIXTURE="${workdir}/tabex_v9.8.7_darwin_arm64.tar.gz" \
  "${workdir}/repo/scripts/update-tabex.sh"

formula="${workdir}/repo/Formula/tabex.rb"
ruby -c "${formula}" >/dev/null
grep -Fq 'version "9.8.7"' "${formula}"
grep -Fq 'url "https://github.com/shpitdev/pkgbuilds/releases/download/tabex-v9.8.7/tabex_v9.8.7_darwin_arm64.tar.gz"' "${formula}"
if grep -Eq 'GitHubReleaseDownloadStrategy|Authorization: Bearer|api.github.com/repos/shpitdev/tabex' "${formula}"; then
  echo "Generated Tabex formula still requires private GitHub access." >&2
  exit 1
fi
