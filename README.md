# SHPIT Homebrew Tap

Homebrew formulae for SHPIT command-line tools.

This repo is the tap source of truth. Formulae are updated by repo-owned scripts and CI, not pushed in from each source repo.

## Packages

| Formula | Upstream | Notes |
|---|---|---|
| `tabex` | `shpitdev/tabex` GitHub Releases | Private darwin arm64 release asset fetched through the GitHub Releases API. The formula reads `HOMEBREW_GITHUB_API_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`, or `SHPIT_GH_TOKEN`, and falls back to `gh auth token` when available. |
| `osyrra` | `shpitdev/osyrra` GitHub Releases | Private darwin arm64 release asset fetched through the GitHub Releases API. Same auth path as `tabex`. |

## Automation

- `.github/workflows/version-bumps.yml` runs on a schedule or manual dispatch, refreshes formula versions/checksums, and opens or updates a PR.
- `.github/workflows/validate.yml` checks Ruby syntax and verifies that the generated formulae are in sync with the updater scripts.

## Usage

Once the GitHub repo exists as `shpitdev/homebrew-tap`:

```bash
brew tap shpitdev/tap
brew install shpitdev/tap/tabex
brew install shpitdev/tap/osyrra
```

If `gh` is not installed or not logged in locally, run installs with an explicit token:

```bash
HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)" brew install shpitdev/tap/tabex
HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)" brew install shpitdev/tap/osyrra
```

After `brew install shpitdev/tap/tabex`, start with:

```bash
tabex --help
```

The formula caveat intentionally points at the installed release surface rather than assuming newer unreleased setup commands.

## Current Limitation

- Both formulae are macOS arm64 only. The upstream releases do not ship a `darwin_amd64` asset today; add one upstream and the updater scripts can gain an `on_intel` block.
- Both upstreams are private repos, so this tap is SHPIT-internal until release assets become public.
- Automation can read those releases with the `SHPIT_GH_TOKEN` secret.

## Local Usage

Update formulae:

```bash
./scripts/update-formulae.sh auto
```

Validate formulae:

```bash
./scripts/validate-formulae.sh
```

## Adding a New Formula

1. Create `Formula/<name>.rb`.
2. Add a dedicated updater script in `scripts/` if the formula should auto-track upstream releases.
3. Extend `./scripts/update-formulae.sh`.
4. Keep the tap README and setup docs aligned with whatever auth story the formula actually requires.
