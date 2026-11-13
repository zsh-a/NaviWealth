# ADR 0002: Personal, Local-Only Scope For The NSH Client

Status: accepted. Partially supersedes [ADR 0001](0001-nsh-client-migration.md).

Date: 2026-11-13.

## Context

ADR 0001 planned to port the whole Flutter LifeOS to NSH and keep the two
clients interoperable through Sync v3. The product owner then decided:

- The app is primarily for the owner's own use.
- Holdings detail must be kept.
- Health is meals, weight and Garmin data, using Garmin's official Personal
  API launched in October 2026.
- Only local backups for now; no Sync.

[Product Scope](../../product/product-scope.md) lists the kept and removed
features. The migration becomes a reduced rewrite, not a port.

## Decision

1. **No parity target.** The Flutter client is frozen and later retired. The
   NSH client implements only Product Scope; KnowledgeOS, ExecutionOS, AI chat,
   agents, Memory Runtime, proposals and the removed Finance tools are not
   ported.
2. **Local-only.** The NSH client has no Sync, account or login, and does not
   call the backend. `crates/sync-wire` is not built. Sync v3 and the backend
   keep serving the frozen Flutter client until it retires, then are archived.
   Production coexistence of both clients on one account is therefore moot;
   the ADR 0001 open decision is closed.
3. **Data continuity by import.** Kept records move once from Flutter into
   NSH through a one-time importer. Prefer reading the existing Flutter backup
   archive from Rust; if that format is unsuitable, a minimal Flutter exporter
   is an allowed exception to the freeze. The full Flutter backup is kept as
   an archive file for removed domains.
4. **Smaller package set.**

   | Package | Owns |
   |---|---|
   | `crates/lifeos-core` | SQLite storage, migrations, clock, encrypted backup export/restore, Flutter import framework; extracted from `apps/nsh-client/src/data/db.rs` once Finance needs it |
   | `crates/finance-core` | Accounts, transactions, categories, budget, statement parsers, receipt recognition, securities, trades, quotes, FX, derived positions and net worth |
   | `crates/health-core` | Meal recognition and nutrition (existing), meals, weight, Garmin Personal API client and daily summaries |
   | `apps/nsh-client` | Four tabs, settings, UI components; fixed composition |

   No `knowledge-core`, `execution-core`, `lifeos-ai` or `DomainPack`-style
   registry. Recognition calls use `llm-protocol` / `llm-client` from the Agent
   Runtime submodule directly; the Agent Runtime loop is not hosted.
5. **No SQLCipher, no Keystore (2026-11-13).** NSH's standalone Android
   APK is packaged from a prebuilt runtime without Gradle: there is no place
   for Kotlin code and no JavaVM handed to Rust, so Keystore would need an
   unsafe JNI shim (Android 12+ only) or a different host app. For a
   personal single-device app this is not worth it. The database is plain
   SQLite in the app's private directory, protected by the Android sandbox
   and file-based encryption; model and Garmin credentials stay in
   app-private storage. Exported backups are the files that leave the
   sandbox, so they are encrypted with a passphrase. Revisit if NSH exposes
   JNI or host plugins to standalone apps.
6. **Garmin through the Personal API.** Use the self-serve personal key and
   its token flow, read-only. The key and tokens stay in app-private
   storage and never enter exported backups. The reverse-engineered client in `lifeos_native` is not
   ported. Endpoint changes or failures keep the last imported data visible.

Unchanged from ADR 0001: Flutter freeze, Android only (no Web, no iOS),
domain truth in Rust crates with UI only in `apps/nsh-client`, no backend
AI relay, NSH 0.5.0 pinned behind local UI adapters. ADR 0001's SQLCipher and
Keystore requirements are replaced by decision 5.

## Consequences

- Delivery starts with Health on the existing meal client; Finance follows
  (see the roadmap).
- The rewrite covers roughly the ledger, import, holdings, meals, weight and
  Garmin — a small fraction of the 320,000-line Flutter client.
- Losing Sync means one device: a lost phone without a recent exported backup
  loses data. Automatic local backups plus manual export mitigate this;
  reconsider Sync only if a second device becomes a real need (new ADR).
- Removed features stay available only in the archived Flutter backup.
- Garmin's Personal API is new and documented mostly by third parties at the
  time of writing; Phase 1 must verify it against Garmin's own documentation.
