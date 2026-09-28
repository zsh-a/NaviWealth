# market-data-rs SDK snapshot

This directory contains the SDK crate used by NaviWealth, not the standalone
CLI/HTTP application. See [VENDORED.md](VENDORED.md) for upstream revision and
update rules, and [LICENSE](LICENSE) for the MIT license.

- SDK: `crates/market-data` (no default SQLite feature).
- Provider extension example: [custom_provider.rs](crates/market-data/examples/custom_provider.rs).
- Host integration and verification: [Market Data Providers](../../docs/domains/market-data-providers.md).
- Native bridge: `apps/mobile/native/lifeos_native/src/api/market.rs` in the host repository.

The independent `market-data-rs` repository owns SDK development and its
CLI/HTTP documentation. This snapshot's crate sources are unchanged; host
routing, persistence and business policy belong to NaviWealth.
