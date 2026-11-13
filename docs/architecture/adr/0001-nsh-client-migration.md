# ADR 0001: Migrate The Client To NSH

Status: accepted direction; partially superseded by
[ADR 0002](0002-personal-local-scope.md) (2026-11-13). ADR 0002 replaces the
target packages, Data Continuity (Sync v3 coexistence), the in-process Agent
Runtime plan and the delivery gates below; the Flutter freeze, NSH direction
and Android-only scope still hold.

Date: 2026-11-13.

## Context

The client direction is NSH, starting from the Rust meal client in
`apps/nsh-client/` on [longbridge/nsh](https://github.com/longbridge/nsh)
0.5.0. It will progressively replace the roughly 320,000-line Flutter client.
The old LifeOS/Finance Now/Next plans and product-discovery sequencing are
superseded by the [migration roadmap](../../roadmap/roadmap-lifeos.md).

Reusable Rust assets already exist: the backend, `crates/health-core`,
`apps/mobile/native/lifeos_native/`, and the `third_party/agent-runtime`
submodule, including `llm-protocol`, `llm-client`, and `agent-chat`.
The meal client is a working seed, not yet a synced LifeOS replacement.
Its meals use NSH KV storage and its API key is currently plaintext in KV.
NSH's built-in 5 MB KV store cannot hold the business database.

## Decision

Freeze Flutter (`apps/mobile`): bug fixes only; new features belong in NSH
and Rust crates. Move domain truth, repositories, and confirmed business
side effects into domain-owned Rust crates. This explicitly supersedes the
Northstar restrictions that kept domain truth in the Dart Host and prohibited
a broad Rust engine. It does not change domain isolation, local-first
ownership, user confirmation, or the Sync v3 protocol.

### Target Ownership

The following are target packages, not a claim that all already exist:

| Package | Owns |
|---|---|
| `crates/lifeos-core` | Domain-neutral rusqlite + SQLCipher persistence infrastructure, HLC, outbox, Sync v3 client, audit, encrypted backup/restore |
| `crates/sync-wire` | Shared Sync v3 envelopes and each table's JSON row-format specification, used by backend and clients |
| `crates/finance-core` | Finance models, calculations, repositories, confirmed writes, and domain tools |
| `crates/health-core` | Health models, meal recognition and nutrition, repositories, confirmed writes, and domain tools |
| `crates/knowledge-core` | Notes, decisions, relations, repositories, and domain tools |
| `crates/execution-core` | Plans, actions, progress, repositories, and domain tools |
| `crates/lifeos-ai` | In-process Agent Runtime host and domain-tool trait registration; replaces the FRB host adapter |
| `apps/nsh-client` | UI, navigation, presentation adapters, and app composition through Rust traits and a domain registry |
| `apps/nsh-host-android` if needed | Kotlin host-channel plugins for Keystore, Health Connect, and background tasks |

Domain crates depend on neutral infrastructure, never on sibling domain
business models. UI and app composition assemble domain registrations; they
do not own authoritative calculations or repository writes. Preserve the
`DomainPack` idea as Rust traits plus a registry rather than copying Flutter
providers or scattering domain switches. The existing Flutter registry stays
the inventory for that frozen client during migration.

`sync-wire` specifies interoperability without moving business policy into
the backend. The backend remains a generic versioned-blob store. SQLCipher
provides encryption at rest; it does not imply Sync E2EE. NSH KV is reserved
for small non-secret preferences. Move API credentials to Android Keystore
through a host-channel plugin, and keep keys out of Sync and exports.

### Data Continuity

NSH is another Sync v3 client. Keep `POST /sync`, row-state LWW, HLC,
accepted acknowledgements, tombstones, and domain reset generations intact.
Use the existing `fin:`, `health:`, `know:`, and `exec:` namespaces and exact
existing table JSON formats. The first shared row family is
`health:health_meals`.

Migrate existing users by pulling their server rows into the new encrypted
SQLite database. Do not convert or open Drift files from NSH. Unsynced
Flutter data must reach the server before cutover; local-only data and photos
need explicit retention/export handling rather than assumed Sync coverage.
Do not delete Flutter storage as a side effect of initial NSH sign-in.

Flutter and NSH can technically use the same account during migration. The
recommendation is to allow coexistence and use bidirectional meal visibility
as the Phase 2 acceptance gate; product authorization remains an open decision.
Until decided, validate with test accounts and retain the frozen Flutter client.

### AI And Platform Boundaries

Run Agent Runtime in process through `lifeos-ai`; keep provider protocols
and host transport separate. Domain tools retain their owning domain's
validation, explicit confirmation, and audit boundaries. There is no backend
AI relay or cloud fallback. Remove FRB and `lifeos_native` only after their
callers and native capabilities have replacements.

Use NSH host channels for Android-only services. The NSH client targets
Android; desktop builds exist only for development and headless tests. Web is
out of scope: the existing Flutter Web build stays frozen and is retired with
Flutter in Phase 6, and no NSH Web probe is scheduled. iOS is out of scope.

## Delivery Gates

The [roadmap](../../roadmap/roadmap-lifeos.md) owns owners, scope, exit evidence,
and stop conditions for these phases:

0. Freeze Flutter, accept this ADR, and replace old planning entry points.
1. Prove Android rusqlite + SQLCipher, Kotlin Keystore over the host channel,
   and `nsh-base` plots against `fl_chart` needs.
2. Build `lifeos-core` and `sync-wire`; move NSH meals to SQLite and Sync v3;
   prove Flutter ↔ NSH bidirectional visibility.
3. Migrate remaining Health, Execution, Knowledge, and the registered shell.
4. Host AI in process and retire FRB / `lifeos_native` after parity evidence.
5. Migrate Finance in batches, starting with accounts, expense, ingest,
   Monthly Close, Runway, and Inbox.
6. Retire Flutter after migration, recovery, and supported-platform acceptance.

## Alternatives And Consequences

Continuing feature development in Flutter would preserve existing widgets and
tests but duplicate future work. Keeping Rust limited to native helpers would
retain the old boundary but prevent reuse of domain truth in the NSH client.
A big-bang rewrite would make the large Finance surface and data migration
hard to verify. The chosen incremental migration uses existing Sync v3
contracts as the interoperability boundary.

NSH 0.5 maturity and dependence on one maintainer are material risks. Keep
NSH behind the local UI adapters, use checked-in lockfiles and a controlled
0.5.0 baseline, and require explicit review plus target-device evidence for
upgrades. Phase 0 does not change dependency constraints or prove platform
support. Finance size requires independently verifiable batches and exact
money/rounding parity. Rewrite Dart widget tests as Rust unit tests and
`nsh-testing` flows; reuse privacy-safe statement corpus fixtures and expected
outcomes where possible. Passing headless tests does not prove an Android
package or Keystore recovery.

## Decisions

Decided 2026-11-13: Web is out of scope (Flutter Web retires with Flutter);
iOS is out of scope. Reopening either needs a new ADR.

Two clients on one account: closed as moot by ADR 0002 (the NSH client is
local-only and imports Flutter data once).

## References

- [Architecture Northstar](../lifeos-architecture-northstar.md)
- [Flutter Shell implementation](../lifeos-shell.md)
- [Sync v3](../../sync/sync-v3.md)
- NSH client baseline: `apps/nsh-client/README.md`
