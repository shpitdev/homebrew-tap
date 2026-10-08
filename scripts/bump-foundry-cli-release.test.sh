#!/usr/bin/env bash
# Behavioral tests with real local git branches; GitHub and updaters are fixtures.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  'api repos/test/repo') echo true ;;
  'pr list') ;;
  'pr create') echo https://github.com/test/repo/pull/1 ;;
  'pr merge') ;;
  'pr view') echo MERGED ;;
  *) echo "Unexpected gh call: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=test/repo
run_case() {
  local name="$1" tag="$2" dry="$3" fail="$4" expected="$5"
  local work="$tmp/$name"
  mkdir -p "$work/scripts"
  git init -q --bare "$tmp/$name.git"
  git init -q -b main "$work"
  cp "$repo_root/scripts/bump-foundry-cli-release.sh" "$work/scripts/"
  mkdir -p "$work/Formula"
  echo '  version "0.0.56"' > "$work/Formula/foundry-cli.rb"
  cat > "$work/scripts/update-foundry-cli.sh" <<'UPDATE'
#!/usr/bin/env bash
printf '  version "%s"\n' "${FOUNDRY_CLI_RELEASE_TAG#v}" > Formula/foundry-cli.rb
UPDATE
  cat > "$work/scripts/validate-formulae.sh" <<'VALIDATE'
#!/usr/bin/env bash
[[ "$FAIL_VALIDATION" != true ]] || exit 1
touch validated
if [[ "$FAIL_VALIDATION" == moved ]]; then
  candidate="$(git branch --show-current)"
  git checkout -q main
  git commit -qm 'Concurrent main update' --allow-empty
  git push -q origin main
  git checkout -q "$candidate"
fi
VALIDATE
  chmod +x "$work"/scripts/*.sh
  (
    cd "$work"
    git config user.name test
    git config user.email test@example.com
    git add .
    git commit -qm initial
    git remote add origin "$tmp/$name.git"
    git push -q -u origin main
    export CALLS="$work/calls" FOUNDRY_CLI_RELEASE_TAG="$tag" DRY_RUN="$dry" FAIL_VALIDATION="$fail"
    : > "$CALLS"
    local status=0
    ./scripts/bump-foundry-cli-release.sh > "$work/output" 2>&1 || status=$?
    [[ "$(git rev-parse origin/main)" == "$(git rev-parse main)" ]]
    case "$expected" in
      noop) [[ "$status" == 0 ]]; ! grep -q 'pr create\|pr merge' "$CALLS" ;;
      invalid) [[ "$status" != 0 ]]; ! grep -q 'pr create\|pr merge' "$CALLS" ;;
      merged) [[ "$status" == 0 ]]; grep -q 'pr create' "$CALLS"; grep -q 'pr merge .*--squash --match-head-commit' "$CALLS"; [[ -f validated ]] ;;
      dry) [[ "$status" == 0 ]]; grep -q 'pr create .*--draft' "$CALLS"; ! grep -q 'pr merge' "$CALLS"; [[ -f validated ]] ;;
      failed) [[ "$status" != 0 ]]; grep -q 'pr create' "$CALLS"; ! grep -q 'pr merge' "$CALLS" ;;
    esac
  )
  echo "Passed: $name"
}
run_case equal v0.0.56 false false noop
run_case older v0.0.55 false false noop
run_case forward v0.0.57 false false merged
run_case numeric v0.0.100 false false merged
run_case dry v0.0.55 true false dry
run_case failed v0.0.57 false true failed
run_case prerelease v0.0.57-next.1 false false invalid
run_case bad-input '../main' false false invalid
run_case moved v0.0.57 false moved failed
