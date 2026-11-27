# Main Branch And Release Policy

`main` is the only long-lived branch. The repository currently permits direct
pushes and has no GitHub branch-protection rule or Ruleset. CI therefore acts as
post-push validation on `main` and as pre-merge validation when contributors
choose to use pull requests.

## CI checks

- `Rust domain crates`: fmt, clippy and tests for `navi-storage`, `navi-finance`,
  `navi-health` and `navi-assistant`, including recognition provider contracts
- `nsh checks`: client fmt, clippy and headless tests, TypeScript formatting,
  mixed NSH type/flow checks, and Android host JVM tests and lint; no signing
  credentials or APK publication
- `Documentation`: first-party document links/code paths, including `llms.txt`
  and the Android host README, plus checker regression tests
- `securities-catalog`: bakes the catalog from `tool/asset_catalog/sources/`
  and republishes the rolling catalog release when they change

Workflows use path filters, so unrelated areas do not start each other's
checks. Automatic client verification is separate from the `nsh client`
manual release workflow, which repeats app and mixed-flow checks before
packaging and signing.

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

## NSH releases

The `nsh client` manual workflow checks `apps/nsh-client` and its mixed flows,
then runs `tool/build-nsh-android-host.sh release` (Gradle unit tests, lint and
assembly). The app-owned host packages the app-linked NSH 0.7.1 native library
and TSX bundle; it preserves the package id and private storage location,
and signs an arm64-v8a APK — `naviwealth-release-arm64-v8a` (the diagnostic
build is `naviwealth-diagnostic-arm64-v8a`) — with the fixed repository
keystore after certificate matching and non-debuggable APK checks pass.
Missing credentials, debug certificates or signature verification failures
stop publication. `tool/sign-nsh-apk.sh` keeps passwords out of command
arguments and removes temporary key material. Do not replace this with
freshly generated debug keys.

A build of an `nsh-v*` tag publishes its own release: the verified APK as
`NaviWealth.apk`, the official NSH update manifest `latest.json`, a
`SHA256SUMS` covering both files, and notes taken from the release commit plus
links to the build and changes since the previous published NSH release in the
tag’s history. Before generating the manifest with the pinned CLI's
`nsh update-manifest`, publication verifies that the `nsh-vX.Y.Z` tag,
`apps/nsh-client/nsh.json` and the Rust package version all match. The manifest
carries the app id, release notes and an Android link to that tag's release page;
Android installation remains an explicit owner action. Releases are titled
after the tag's subject, `NaviWealth NSH vX.Y.Z (build N)` — the earlier
`NaviWealth Health NSH` wording is retired with v0.9.0. Dispatches on a
branch verify without publishing.

The package id is `com.naviwealth.app` (2026-11-15; the earlier
`com.naviwealth.health.nsh` installs migrate by clean-install restore from a
WebDAV backup). Releases use `nsh-vX.Y.Z` tags: build the exact tag with the
manual workflow and publish the verified APK, `latest.json` and `SHA256SUMS`.
A newly created NSH release is marked latest, matching the official updater's
`releases/latest/download/latest.json` source. The rolling securities catalog
is always a prerelease with `--latest=false`, so it cannot replace that source.
Existing historical Flutter release artifacts are not overwritten. Subsequent
releases must retain the fixed key.

The manifest protocol was added on 2026-11-27. Version 0.21.0 is the first
release configured to publish it; local code changes and branch builds do not
publish a manifest or backfill old releases. The GitHub manifest
source requires no additional signing secret. Android APKs continue to use the
fixed release certificate.
