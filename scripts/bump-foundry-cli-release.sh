#!/usr/bin/env bash
# Called only by the isolated foundry-cli workflow job, with a real actor token.
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${FOUNDRY_CLI_RELEASE_TAG:?A stable release tag is required}"
dry_run="${DRY_RUN:-false}"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo 'Expected a stable vX.Y.Z tag' >&2; exit 1; }
[[ "$dry_run" == true || "$dry_run" == false ]] || exit 1
version="${tag#v}"
candidate_paths=(Formula/foundry-cli.rb scripts/validate-formulae.sh)
read_version() { sed -n 's/^  version "\([^"]*\)"$/\1/p' Formula/foundry-cli.rb; }
update_candidate() { ./scripts/update-foundry-cli.sh; }
validate_candidate() { ./scripts/validate-formulae.sh; }

# No secrets are printed; fail before pushing if the existing token is read-only.
gh api "repos/${GITHUB_REPOSITORY:?}" --jq '.permissions.push' | grep -qx true
base_sha="$(git rev-parse HEAD)"
current="$(read_version)"
if [[ "$version" == "$current" ]]; then
  echo "No-op: ${tag} is already packaged."
  exit 0
fi
newest="$(printf '%s\n' "$version" "$current" | sort -V | tail -n1)"
if [[ "$newest" != "$version" && "$dry_run" != true ]]; then
  echo "No-op: refusing downgrade from ${current} to ${version}."
  exit 0
fi
branch="automation/foundry-cli-${tag}"
pr_flags=()
if [[ "$dry_run" == true ]]; then
  branch="automation/dry-run-foundry-cli-${tag}"
  pr_flags+=(--draft)
  echo "Dry run: candidate ${tag}; main remains at ${current}. Merge and publish are disabled."
fi

update_candidate
git checkout -B "$branch"
git add "${candidate_paths[@]}"
if git diff --cached --quiet; then
  echo 'No-op: updater produced no changes.'
  exit 0
fi
git commit -m "chore: bump Foundry CLI to ${version}"
# Capture the old ref before replacing our own deterministic automation branch.
git fetch origin "refs/heads/${branch}:refs/remotes/origin/${branch}" || {
  # A missing branch is expected only on the first run; other failures fail closed.
  [[ -z "$(git ls-remote --heads origin "$branch")" ]]
}
git push --force-with-lease --set-upstream origin "$branch"
head_sha="$(git rev-parse HEAD)"
pr="$(gh pr list --head "$branch" --base main --state open --json number --jq '.[0].number // empty')"
if [[ -z "$pr" ]]; then
  body_file="$(mktemp)"
  printf 'Update only Foundry CLI to %s.\n\nValidated in the originating version-bumps job before any merge. Dry run: %s.\n' "$tag" "$dry_run" > "$body_file"
  pr="$(gh pr create --base main --head "$branch" --title "chore: bump Foundry CLI to ${version}" --body-file "$body_file" "${pr_flags[@]}")"
  rm -f "$body_file"
fi
echo "Candidate PR: ${pr}"
# Deliberately after PR creation: validation failures leave an inspectable open PR.
validate_candidate

git fetch origin main
if [[ "$(git rev-parse origin/main)" != "$base_sha" ]]; then
  echo 'Main changed during validation; rerun against current main before merging.' >&2
  exit 1
fi
if [[ "$dry_run" == true ]]; then
  echo "Dry run passed: validated ${tag}; would merge ${pr} only for a forward release. No merge or publish performed."
  exit 0
fi
# These repos require a PR, but no approvals or required external status checks.
# In-job validation is the gate; a PAT merge triggers normal push workflows.
gh pr merge "$pr" --squash --match-head-commit "$head_sha"
[[ "$(gh pr view "$pr" --json state --jq .state)" == MERGED ]]
echo "Merged ${pr}; normal main push automation is now responsible for publishing."
