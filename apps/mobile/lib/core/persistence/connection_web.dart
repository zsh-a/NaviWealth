import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';

/// Opens the drift connection on the web target.
///
/// Uses [WasmDatabase.open], which auto-selects the best available browser
/// storage in this order: OPFS (shared/locks) → shared IndexedDB →
/// unsafe IndexedDB → in-memory.
QueryExecutor openConnectionImpl({
  required String dbFileName,
  required String? encryptionKey,
}) {
  return DatabaseConnection.delayed(_openWebConnection(dbFileName));
}

Future<DatabaseConnection> _openWebConnection(String dbFileName) async {
  final databaseName = dbFileName.endsWith('.db')
      ? dbFileName.substring(0, dbFileName.length - 3)
      : dbFileName;

  final result = await WasmDatabase.open(
    databaseName: databaseName,
    sqlite3Uri: Uri.parse('/sqlite3.wasm'),
    driftWorkerUri: Uri.parse('/drift_worker.dart.js'),
  );

  if (kDebugMode) {
    AppLogger.instance.d(
      'drift web: opened "$databaseName" via ${result.chosenImplementation.name}'
      '${result.missingFeatures.isEmpty ? '' : ' (missing: ${result.missingFeatures.map((f) => f.name).join(', ')})'}',
    );
  }

  return result.resolvedExecutor;
}
