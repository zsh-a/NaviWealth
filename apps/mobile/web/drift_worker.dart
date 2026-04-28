// Drift web worker entry point.
//
// Compiled to JS by `tool/setup-drift-web.sh` and loaded by
// `WasmDatabase.open` (see lib/core/db/connection_web.dart). Hosting the
// database in a worker lets drift use OPFS / shared IndexedDB modes that
// require off-main-thread execution.
//
// Build (one-shot or in CI):
//   apps/mobile/tool/setup-drift-web.sh
import 'package:drift/wasm.dart';

void main() {
  WasmDatabase.workerMainForOpen();
}
