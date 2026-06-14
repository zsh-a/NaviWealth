#!/usr/bin/env bash
set -euo pipefail

# worker-build 0.8.5 enables wasm-bindgen catch wrappers by default. With
# wasm-bindgen 0.2.125 that path requires an externref table our Worker module
# does not emit, so keep the stable legacy shim path until the upstream tooling
# no longer needs this compatibility switch.
worker-build --release --no-panic-recovery
