#!/usr/bin/env bash
set -euo pipefail

if ! command -v worker-build >/dev/null 2>&1; then
  cargo install -q worker-build
fi

# worker-build 0.8.5 enables wasm-bindgen catch wrappers by default. With
# wasm-bindgen 0.2.125 that path requires an externref table our Worker module
# does not emit, so keep the stable legacy shim path until the upstream tooling
# no longer needs this compatibility switch.
worker-build --release --no-panic-recovery
