# Third-Party Sources

[market-data-rs](market-data-rs/README.md) is the vendored market-data SDK.
Its [revision and update rules](market-data-rs/VENDORED.md) describe how to
refresh the snapshot.

AI recognition and the general assistant use pi-rust through
[`navi-assistant`](../crates/navi-assistant/Cargo.toml). Cargo pins the upstream
revision and resolves it through the committed lockfiles; there is no runtime
submodule to initialize or update.
