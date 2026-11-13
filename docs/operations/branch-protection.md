# Main Branch And Release Policy

`main` is the only long-lived branch. The repository currently permits direct
pushes and has no GitHub branch-protection rule or Ruleset. CI therefore acts as
post-push validation on `main` and as pre-merge validation when contributors
choose to use pull requests.

## CI checks

- `mobile / static checks`
- `mobile / test shard 0..3 / 4`
- `mobile / golden regression (mobile)` (full suite on PRs, `main`, and release)
- `mobile / Web build and smoke / Web build and browser smoke` on PRs and `main`
- `backend / fmt + clippy + test`
- `web-smoke / Web build and browser smoke` for weekly/manual full-browser runs
- `docs / links + strict build` for documentation changes

Workflows use path filters, so unrelated application areas do not start each
other's checks. Test timings are written by each shard; failure events remain
available as artifacts. README screenshot refresh is manual. Android APK/AAB
and native-payload checks run in releases, with related PRs still covered by
the device and native-runtime workflows.

## Optional protected-main setup

If protected-main development is re-enabled, use a Ruleset and require only
checks that are present for the changed paths. Do not require deployment jobs
on pull requests.

## Repository secrets

| Name | Used by |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Worker and Pages deploys |
| `CLOUDFLARE_ACCOUNT_ID` | Worker and Pages deploys |
| `KEYSTORE_BASE64` | Signed Android releases |
| `KEYSTORE_PASSWORD` | Signed Android releases |
| `KEY_ALIAS` | Signed Android releases |
| `KEY_PASSWORD` | Signed Android releases |

## NSH Health releases

The `nsh client` manual workflow builds `apps/nsh-client` and signs its APK
with the same fixed repository keystore secrets above. From `nsh-v0.2.1`
(build 4), it uploads only `naviwealth-health-nsh-release-arm64-v8a` after
certificate matching and non-debuggable APK checks pass. Missing credentials,
debug certificates or signature verification failures stop publication.
`tool/sign-nsh-apk.sh` keeps passwords out of command arguments and removes
temporary key material. Do not replace this with freshly generated debug keys.

NSH Health uses `nsh-vX.Y.Z` tags and its own package identity. Build the exact
tag with the manual workflow and publish the verified APK plus `SHA256SUMS`.
Keep the global latest release unchanged; it belongs to another client channel.
Legacy debug-signed Health installs need a data migration before switching to
this certificate; subsequent Health releases must retain the fixed key.

## Tag-based release flow

`main` is the sole production deployment source for Web and backend. Pages
receives the exact bundle that passed Chromium smoke, after mobile static
checks, all test shards, and full goldens succeed.

Tags drive the Android-only `release.yml`. A tag `vX.Y.Z` must resolve to the
checked-out source and event SHA; versions and build numbers come from that
tag (`git rev-list --count <tag>`). Manual runs must select an existing tag in
the ref picker; branch dispatch fails before quality or build jobs start.
Release quality gates cover mobile, backend contracts, native runtime, and
Android device acceptance. The workflow publishes signed APK/AAB and the
in-app update manifest, without redeploying Web or backend.

```bash
./tool/bump-version.sh 0.9.0
git push origin HEAD --follow-tags
```
