# Branch Protection — `main`

The `main` branch is the only long-lived branch. All changes land via PR.
Configure these rules at **Settings → Branches → Branch protection rules**
for the pattern `main`. (Owner: `@zsh-a`.)

## Required settings

- **Require a pull request before merging**
  - Require approvals: **1**
  - Dismiss stale approvals when new commits are pushed: **on**
  - Require review from Code Owners: **on** (uses `.github/CODEOWNERS`)
  - Require approval of the most recent reviewable push: **on**
- **Require status checks to pass before merging**
  - Require branches to be up to date before merging: **on**
  - Required checks (exact names from workflow `jobs.<id>.name`):
    - `mobile / analyze + test (coverage)`
    - `mobile / build web`
    - `mobile / build android (debug apk)`
    - `mobile / build ios (no codesign)`
    - `backend / fmt + clippy + check (wasm32)`
    - `backend / cargo audit (RUSTSEC)`
    - `codecov/project` (added automatically once Codecov is wired up)
    - `codecov/patch`
- **Require conversation resolution before merging**: on
- **Require linear history**: on
- **Do not allow bypassing the above settings**: on (admins included)
- **Restrict who can push to matching branches**: on (only the merge button)
- **Allow force pushes**: off
- **Allow deletions**: off

## Why path-filtered checks need special handling

`mobile.yml` and `backend.yml` are scoped via `on.pull_request.paths`, so a
PR that only changes one app will not trigger the other. GitHub treats a
required check that did not run as **pending forever**. Two options:

1. (Recommended) Mark every required mobile/backend check as **required
   only when present** — GitHub now honors the path filter and skips the
   gate when the check did not run. Use the new "Rulesets" UI to do this
   per-job; legacy branch protection requires every job to run.
2. (Fallback) Drop the path filter from the workflow `on:` triggers so
   every PR runs every job. Simpler, slower.

We use option (1) via Rulesets.

## Repository secrets

Set these at **Settings → Secrets and variables → Actions**:

| Name             | Used by                          | Required? |
| ---------------- | -------------------------------- | --------- |
| `CODECOV_TOKEN`  | `mobile.yml` coverage upload     | Public repos: optional. Private: required. |

`GITHUB_TOKEN` is auto-provisioned by Actions; no setup needed.

## Tag-based release flow

Tags drive release builds (see `.github/workflows/release.yml`):

- `mobile-vX.Y.Z`  → web bundle + APK + AAB
- `backend-vX.Y.Z` → Workers WASM bundle

Build numbers are derived from `git rev-list --count <tag>` so they are
monotonically increasing and reproducible from history.

Cut a release with the helper script:

```bash
./tool/bump-version.sh 0.2.0              # stamps both mobile + backend, tags v0.2.0
git push origin main --follow-tags
```
