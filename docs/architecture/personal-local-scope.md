# Personal, Local-Only Scope

Status: accepted.

Date: 2026-11-13. Updated 2026-11-15 after the Flutter retirement.

## Context

The product owner decided how far the NSH rewrite goes:

- The app is primarily for the owner's own use.
- Holdings detail must be kept.
- Health is meals, weight and Garmin data, using Garmin's official Personal
  API launched in October 2026.
- Only local backups for now; no Sync.

[Product Scope](../product/product-scope.md) lists the kept and removed
features. The migration became a reduced rewrite, not a port.

## Decision

1. **No parity target.** The Flutter client was retired (2026-11-15) with its
   source archived at the `flutter-final` tag. The NSH client implements only
   Product Scope; KnowledgeOS, ExecutionOS, AI chat, agents, Memory Runtime,
   proposals and the removed Finance tools are not ported.
2. **Local-only.** The NSH client has no Sync, account or login, and does not
   call a backend. `sync-wire` was never built; Sync v3 and the
   backend retired with Flutter.
3. **Data continuity by archive.** The one-time Flutter import was cut
   (2026-11-15). The exported Flutter backup archive is the record of removed
   data; nothing imports it.
4. **Small package set.**

   | Package | Owns |
   |---|---|
   | `crates/navi-storage` | SQLite storage, migrations, clock, encrypted backup export/restore |
   | `crates/navi-finance` | Accounts, transactions, categories, budget, statement parsers, securities, trades, quotes, FX, derived positions and net worth |
   | `crates/navi-health` | Meal recognition and nutrition, meals, weight, Garmin Personal API client and daily summaries |
   | `apps/nsh-client` | Four tabs, settings, UI components; fixed composition |

   No `knowledge-core`, `execution-core` or domain registry. Recognition calls
   use `llm-protocol` / `llm-client` from the Agent Runtime submodule
   directly; the Agent Runtime loop is not hosted.
5. **No SQLCipher, no Keystore (2026-11-13).** NSH's standalone Android APK
   is packaged from a prebuilt runtime without Gradle: there is no place for
   Kotlin code and no JavaVM handed to Rust, so Keystore would need an unsafe
   JNI shim (Android 12+ only) or a different host app. For a personal
   single-device app this is not worth it. The database is plain SQLite in
   the app's private directory, protected by the Android sandbox and
   file-based encryption; model and Garmin credentials stay in app-private
   storage. Exported backups are the files that leave the sandbox, so they
   are encrypted with a passphrase. Revisit if NSH exposes JNI or host
   plugins to standalone apps.
6. **Garmin through the Personal API.** Use the self-serve personal key and
   its token flow, read-only. The key and tokens stay in app-private storage
   and never enter exported backups. The reverse-engineered client is not
   ported. Endpoint changes or failures keep the last imported data visible.

Also holds: Android only (no Web, no iOS), domain truth in Rust crates with
UI only in `apps/nsh-client`, no backend AI relay, NSH 0.5.0 pinned behind
local UI adapters.

## Consequences

- Delivery starts with Health on the existing meal client; Finance follows
  (see the roadmap).
- Losing Sync means one device: a lost phone without a recent exported backup
  loses data. Automatic local backups plus manual export mitigate this;
  reconsider Sync only if a second device becomes a real need (new decision).
- Removed features stay available only in the archived Flutter backup.
- Garmin's Personal API was verified against Garmin's own documentation and
  a real key (2026-11-13).
