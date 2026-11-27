# Personal, Local-Only Scope

Status: accepted.

Date: 2026-11-13. Updated 2026-11-27 for the owner-authorized local general assistant.

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
   Product Scope; KnowledgeOS, ExecutionOS, the Flutter named agents and Memory
   Runtime, and the removed Finance tools are not ported. The owner authorized
   a new general assistant on 2026-11-27 with persistent conversations,
   cross-task memory, web research and multi-step tasks.
2. **Local-only.** The NSH client has no Sync, account or login, and does not
   call a backend. `sync-wire` was never built; Sync v3 and the
   backend retired with Flutter.
3. **Data continuity by archive.** The one-time Flutter import was cut
   (2026-11-15). The exported Flutter backup archive is the record of removed
   data; nothing imports it.
4. **Small package set.**

   | Package | Owns |
   |---|---|
   | `crates/navi-storage` | Neutral SQLite opening, migration execution, snapshots and atomic table replacement |
   | `crates/navi-finance` | Accounts, transactions, categories, budget, statement parsers, securities, trades, quotes, FX, derived positions and net worth |
   | `crates/navi-health` | Meal/favorite models and validated repositories, nutrition, weight and review calculations, Garmin request/parsing contracts |
   | `crates/navi-assistant` | Embedded pi-rust Agent loop, provider adaptation, bounded execution and replay contracts |
   | `apps/nsh-client` | Four tabs, settings, reactive adapters, device clock/photos/network, encrypted backup orchestration and cross-domain capture/scale transactions |

   No `knowledge-core`, `execution-core` or domain registry. Recognition and
   the general assistant use pinned pi-rust `rpi-agent` / `rpi-ai` through
   `navi-assistant`. Recognition is a single-turn draft operation; only the
   general assistant uses the multi-step Agent loop. The app owns SQLite sessions,
   memory, permissions and business tools; NSH remains the UI. The pi-rust CLI,
   desktop shell/file tools, plugin loader and server are not part of the app.
5. **No SQLCipher, no Keystore (2026-11-13; host clarification 2026-11-18).**
   The database is plain SQLite in the app's private directory, protected by
   the Android sandbox and file-based encryption; model and Garmin credentials
   stay in app-private storage. Exported backups are the files that leave the
   sandbox, so they are encrypted with a passphrase. The app-owned Gradle host
   now supplies Kotlin hardware integration for the scale; native access is
   technically available. That implementation does not expand the personal
   single-device credential-storage policy or add Keystore to this scope.
6. **Garmin through the Personal API.** Use the self-serve personal key and
   its token flow, read-only. The key and tokens stay in app-private storage
   and never enter exported backups. The reverse-engineered client is not
   ported. Endpoint changes or failures keep the last imported data visible.
7. **Assistant remains local-first.** Agent execution and durable state live on
   the phone. Model requests go directly to the configured user-owned profile;
   optional Brave Search queries and public-page fetches are explicit external
   tool requests. There is no NaviWealth backend, AI relay or background daemon.
   Before the first send to a model destination, separate consent covers chat,
   retrieved memories and requested local records. Saving memory requires
   owner confirmation; business changes use the existing capture review and
   atomic commit. Conversation and memory tables enter encrypted backups;
   model/search keys do not. Process death never authorizes tool replay.

Also holds: Android only (no Web, no iOS), domain truth in Rust crates with
UI only in `apps/nsh-client`, no backend AI relay, NSH 0.7.1 pinned behind
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
