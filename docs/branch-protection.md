# Branch Protection — `main`

`main` is the only long-lived branch. All changes land via PR.
Configure at **Settings → Branches → Branch protection rules** for `main` (Owner: `@zsh-a`).

## Required settings

- **Require a pull request before merging**
  - Approvals: **1**; dismiss stale approvals on new pushes; require Code Owner review (uses `.github/CODEOWNERS`); require approval of the most recent reviewable push.
- **Require status checks to pass before merging** (branches must be up to date)
  - `mobile / analyze + test (coverage)`
  - `mobile / golden regression (mobile)`
  - `mobile / build web`
  - `backend / fmt + clippy + check (wasm32)`
  - `codecov/project`, `codecov/patch` (auto once Codecov is wired up)
- **Require conversation resolution**: on
- **Require linear history**: on
- **Do not allow bypassing the above settings**: on (admins included)
- **Restrict who can push to matching branches**: on (only the merge button)
- **Allow force pushes / deletions**: off

`security.yml` (cargo audit, Trivy, dart pub outdated) is weekly + lockfile-triggered, not a per-PR gate.

## Path-filtered checks

`mobile.yml` and `backend.yml` are scoped via `on.pull_request.paths`, so a PR that only touches one app won't trigger the other. GitHub treats a non-running required check as **pending forever**. Two options:

1. **(Recommended)** Use **Rulesets** → mark each required check as "required only when present"; GitHub honors the path filter and skips the gate when the check did not run.
2. (Fallback) Drop the path filter from `on:` so every PR runs every job. Simpler, slower.

We use option 1 via Rulesets.

## Repository secrets

Set at **Settings → Secrets and variables → Actions**:

| Name | Used by | Required? |
|------|---------|-----------|
| `CODECOV_TOKEN` | `mobile.yml` coverage upload | Public repos: optional. Private: required. |

`GITHUB_TOKEN` is auto-provisioned.

## Tag-based release flow

Tags drive `release.yml`. A single tag `vX.Y.Z` stamps and builds both mobile and backend; build numbers come from `git rev-list --count <tag>` (monotonic, reproducible).

```bash
./tool/bump-version.sh 0.4.1            # stamps mobile + backend, commits, tags v0.4.1
git push origin HEAD --follow-tags      # triggers release.yml
```
