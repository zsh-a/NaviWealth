# Main Branch And Release Policy

`main` is the only long-lived branch. The repository currently permits direct
pushes and has no GitHub branch-protection rule or Ruleset. CI therefore acts as
post-push validation on `main` and as pre-merge validation when contributors
choose to use pull requests.

## CI checks

- `Rust domain crates`: fmt, clippy and tests for `navi-storage`, `navi-finance`
  and `navi-health`, plus fmt and tests for the `third_party/agent-runtime`
  submodule
- `securities-catalog`: bakes the catalog from `tool/asset_catalog/sources/`
  and republishes the rolling catalog release when they change

Workflows use path filters, so unrelated areas do not start each other's
checks. The `nsh client` workflow runs only on manual dispatch and checks
the app crate before packaging.

## Optional protected-main setup

If protected-main development is re-enabled, use a Ruleset and require only
checks that are present for the changed paths.

## Repository secrets

| Name | Used by |
|---|---|
| `KEYSTORE_BASE64` | Signed NSH Android releases |
| `KEYSTORE_PASSWORD` | Signed NSH Android releases |
| `KEY_ALIAS` | Signed NSH Android releases |
| `KEY_PASSWORD` | Signed NSH Android releases |

## NSH Health releases

The `nsh client` manual workflow builds `apps/nsh-client` and signs its APK
with the fixed repository keystore secrets above. From `nsh-v0.2.1`
(build 4), it uploads only `naviwealth-health-nsh-release-arm64-v8a` after
certificate matching and non-debuggable APK checks pass. Missing credentials,
debug certificates or signature verification failures stop publication.
`tool/sign-nsh-apk.sh` keeps passwords out of command arguments and removes
temporary key material. Do not replace this with freshly generated debug keys.

NSH Health uses `nsh-vX.Y.Z` tags and its own package identity. Build the exact
tag with the manual workflow and publish the verified APK plus `SHA256SUMS`.
Do not republish the global latest release; it still holds the retired
Flutter channel's artifacts.
Legacy debug-signed Health installs need a data migration before switching to
this certificate; subsequent Health releases must retain the fixed key.
