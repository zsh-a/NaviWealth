import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

/// Opens the drift connection on the web target.
///
/// Uses [WasmDatabase.open], which auto-selects the best available browser
/// storage in this order: OPFS (shared/locks) → shared IndexedDB →
/// unsafe IndexedDB → in-memory. The choice is logged in debug builds so the
/// degraded fallback (e.g. private-mode Safari without OPFS) is observable.
///
/// **At-rest encryption is intentionally not wired here yet.** Native targets
/// use SQLCipher via `sqlcipher_flutter_libs`; the equivalent on the web
/// requires either a SubtleCrypto-based `WasmDatabaseSetup` or a SQLCipher
/// WASM build. That work is tracked as a follow-up under FIR-35 — until it
/// lands, [encryptionKey] is accepted but unused on web. The same is true on
/// disk: data lives in IndexedDB / OPFS as plaintext sqlite pages.
QueryExecutor openConnectionImpl({
  required String dbFileName,
  required String encryptionKey,
}) {
  return DatabaseConnection.delayed(_openWebConnection(dbFileName));
}

Future<DatabaseConnection> _openWebConnection(String dbFileName) async {
  // WasmDatabase persists per `databaseName`, so strip the `.db` suffix used
  // on native — IndexedDB / OPFS keys are bare names by convention.
  final databaseName = dbFileName.endsWith('.db')
      ? dbFileName.substring(0, dbFileName.length - 3)
      : dbFileName;

  final result = await WasmDatabase.open(
    databaseName: databaseName,
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.dart.js'),
  );

  if (kDebugMode) {
    // ignore: avoid_print
    print(
      'drift web: opened "$databaseName" via ${result.chosenImplementation.name}'
      '${result.missingFeatures.isEmpty ? '' : ' (missing: ${result.missingFeatures.map((f) => f.name).join(', ')})'}',
    );
  }

  return result.resolvedExecutor;
}
