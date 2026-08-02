# SHPIT Homebrew Tap

Homebrew formulae for SHPIT command-line tools.

This repo is the tap source of truth. Formulae are updated by repo-owned scripts and CI, not pushed in from each source repo.

## Packages

| Formula | Upstream | Notes |
|---|---|---|
| `foundry-cli` | `shpitdev/foundry-cli` GitHub Releases | Private darwin arm64 and amd64 release assets fetched through the GitHub Releases API, with release-provided SHA-256 digests verified before formula generation. Uses the standard tap authentication path. |
| `meshix-cli` | `shpitdev/meshix-observability` GitHub Releases | Private darwin arm64 release asset fetched through the GitHub Releases API. The formula first checks `HOMEBREW_GITHUB_API_TOKEN`, `GH_TOKEN`, and `GITHUB_TOKEN`, then falls back to `gh auth token`, and only then checks `SHPIT_GH_TOKEN` for SHPIT automation environments. |
| `tabex` | `shpitdev/pkgbuilds` GitHub Releases | Public darwin arm64 binary mirrored from the private Tabex release after digest and archive verification. Mirrored versions install anonymously. |
| `osyrra` | `shpitdev/osyrra` GitHub Releases | Private darwin arm64 release asset fetched through the GitHub Releases API. Same auth path as `meshix-cli`. |

## Automation

- `.github/workflows/version-bumps.yml` runs on a schedule or manual dispatch, refreshes formula versions/checksums, and opens or updates a PR.
- `.github/workflows/validate.yml` checks Ruby syntax and verifies that the generated formulae are in sync with the updater scripts.

## Usage

Once the GitHub repo exists as `shpitdev/homebrew-tap`:

```bash
brew tap shpitdev/tap
brew install shpitdev/tap/foundry-cli
brew install shpitdev/tap/meshix-cli
brew install shpitdev/tap/tabex
brew install shpitdev/tap/osyrra
```

If `gh` is not installed or not logged in locally, run installs with an explicit token:

```bash
HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)" brew install shpitdev/tap/meshix-cli
HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)" brew install shpitdev/tap/foundry-cli
# Required for the legacy Tabex v0.0.11 formula only.
HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)" brew install shpitdev/tap/tabex
HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)" brew install shpitdev/tap/osyrra
```

After `brew install shpitdev/tap/tabex`, start with:

```bash
tabex setup
```

That saves browser config, installs or updates the managed Chrome extension locally, and prints the Chrome load or refresh steps.

## Current Limitation

- `meshix-cli`, `tabex`, and `osyrra` are macOS arm64 only. `foundry-cli` also supports macOS Intel.
- `foundry-cli`, `meshix-cli`, and `osyrra` currently come from private upstream repos, so those install paths remain SHPIT-internal until their release assets become public.
- Tabex `v0.0.11` predates the public binary channel and still requires private GitHub access. The first Tabex version mirrored through `shpitdev/pkgbuilds` and later versions install anonymously; automation will replace the legacy formula when that release exists.
- Automation reads private releases for the other formulae with the `SHPIT_GH_TOKEN` secret, but local installs should usually rely on your logged-in `gh` session or one of the standard Homebrew GitHub token env vars.

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
