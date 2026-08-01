# Main Branch And Release Policy

`main` is the only long-lived branch. The repository currently permits direct
pushes and has no GitHub branch-protection rule or Ruleset. CI therefore acts as
post-push validation on `main` and as pre-merge validation when contributors
choose to use pull requests.

## CI checks

- `mobile / static checks`
- `mobile / test shard 0..3 / 4`
- `mobile / test timing summary`
- `mobile / responsive task-flow goldens` on pull requests
- `mobile / golden regression (mobile)` on `main`
- `mobile / build Android arm64 AAB`
- `mobile / build web` on `main`
- `backend / fmt + clippy + test`
- `web-smoke / web smoke (...)` for web-relevant pull requests
- `docs / links + strict build` for documentation changes

Workflows use path filters, so unrelated application areas do not start each
other's checks.

## Optional protected-main setup

If protected-main development is re-enabled, use a Ruleset and require only
checks that are present for the changed paths. Do not require push-only jobs
such as `golden regression (mobile)` or `build web` on pull requests.

## Repository secrets

| Name | Used by |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Worker and Pages deploys |
| `CLOUDFLARE_ACCOUNT_ID` | Worker and Pages deploys |
| `KEYSTORE_BASE64` | Signed Android releases |
| `KEYSTORE_PASSWORD` | Signed Android releases |
| `KEY_ALIAS` | Signed Android releases |
| `KEY_PASSWORD` | Signed Android releases |
## Tag-based release flow

Tags drive `release.yml`. A tag `vX.Y.Z` builds Android and Web artifacts from
the committed source and optionally deploys the backend. Build numbers come
from `git rev-list --count <tag>`.

```bash
./tool/bump-version.sh 0.9.0
git push origin HEAD --follow-tags
```
