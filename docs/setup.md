# Setup

## Temporary Mode

Use this first.

1. Create the GitHub repository as `shpitdev/homebrew-tap`.
2. Push this repo.
3. In `Settings -> Actions -> General`:
   - set workflow permissions to `Read and write`
   - enable `Allow GitHub Actions to create and approve pull requests`
4. Attach the `SHPIT_GH_TOKEN` secret to `homebrew-tap` so private SHPIT formulae can update automatically.
5. Run the `version-bumps` workflow manually.

Result:

- branch and PR creation use the repo `GITHUB_TOKEN`
- private SHPIT formula refreshes work only if the repo can read `SHPIT_GH_TOKEN`
- there is no separate publish workflow because the tap repo itself is the distribution surface
- upstream `tabex` and `osyrra` release workflows can also trigger this workflow automatically with `gh workflow run version-bumps.yml`, but that depends on `SHPIT_WORKFLOW_DISPATCH_TOKEN` being available in their Depot CI repo secrets

## GitHub UI Links

- create PAT: <https://github.com/settings/personal-access-tokens>
- review active org PATs: <https://github.com/organizations/shpitdev/settings/personal-access-tokens/active>
- manage org Actions secrets: <https://github.com/organizations/shpitdev/settings/secrets/actions>

## SHPIT_GH_TOKEN

Create the secret (org-level or repo-level) with access to read private releases on `shpitdev/tabex` and `shpitdev/osyrra`. An org-level secret with `selected` visibility works well if you consume it from multiple repos.

Attach it to this repo with:

```bash
gh secret set SHPIT_GH_TOKEN \
  --org shpitdev \
  --repos homebrew-tap \
  --body "$(gh auth token)"
```

## SHPIT_WORKFLOW_DISPATCH_TOKEN

Create a fine-grained PAT that can trigger workflow dispatches in:

- `shpitdev/homebrew-tap`
- `shpitdev/pkgbuilds`

Store that PAT as the GitHub org secret `SHPIT_WORKFLOW_DISPATCH_TOKEN` with `selected` visibility for these producer repos:

- `shpitdev/tabex`
- `shpitdev/osyrra`

Those producer release workflows run in Depot CI, so GitHub org secrets are not enough on their own. Mirror the same secret into Depot for each producer repo with one of these paths:

```bash
cd /home/anandpant/Development/shpitdev/tabex
depot ci migrate secrets-and-vars -y

cd /home/anandpant/Development/shpitdev/osyrra
depot ci migrate secrets-and-vars -y
```

Or add the Depot secrets directly:

```bash
depot ci secrets add SHPIT_WORKFLOW_DISPATCH_TOKEN --repo shpitdev/tabex
depot ci secrets add SHPIT_WORKFLOW_DISPATCH_TOKEN --repo shpitdev/osyrra
```

## Local Operator Flow

If you are logged into GitHub locally with `gh auth login`, you can run:

```bash
./scripts/update-formulae.sh all
./scripts/validate-formulae.sh
```

That uses your local GitHub CLI session for private release access.

For local `brew install shpitdev/tap/tabex`, the formula uses the same auth path:

- it first checks `HOMEBREW_GITHUB_API_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`, and `SHPIT_GH_TOKEN`
- if none are set, it falls back to `gh auth token`
- in headless environments, prefer `HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)" brew install ...`

## Package-Manager Install Behavior

Both private formulae use install-side GitHub auth:

- they check `HOMEBREW_GITHUB_API_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`, and `SHPIT_GH_TOKEN`
- if no token env var is present, they fall back to `gh auth token`

Both `tabex` and `osyrra` are macOS arm64 only today. An Intel Mac install will fail with an architecture guard until the upstream release adds a `darwin_amd64` asset and the formulae gain an `on_intel` block.

## Recommended Follow-Up

1. Confirm `SHPIT_GH_TOKEN` is attached to this repo.
2. Validate real `brew install shpitdev/tap/tabex` and `brew install shpitdev/tap/osyrra` flows on a macOS arm64 machine with a user who has access to the private upstream repos.
3. Keep the package-manager caveats aligned with the upstream installers when shell or setup UX changes.
