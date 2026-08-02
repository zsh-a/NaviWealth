#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash tool/setup-drift-web.sh
flutter build web "$@"

# Recent Flutter releases copy only recognized web entrypoints. Drift's
# generated root assets therefore need an explicit, post-build install.
install -m 0644 web/sqlite3.wasm build/web/sqlite3.wasm
install -m 0644 web/drift_worker.dart.js build/web/drift_worker.dart.js

echo "web release ready with Drift assets in build/web/"
