import 'package:drift/drift.dart';

import 'connection_stub.dart'
    if (dart.library.io) 'connection_native.dart'
    if (dart.library.html) 'connection_web.dart';

/// Opens a [QueryExecutor] for [AppDatabase].
///
/// On iOS / Android / desktop the connection is backed by SQLCipher and
/// keyed with [encryptionKey] (a hex-encoded 256-bit key). On the web the
/// returned executor is non-persistent — the proper Web implementation
/// (drift WASM + IndexedDB + Crypto API) is owned by the FIR-2 web track
/// and will replace the stub later.
QueryExecutor openAppConnection({
  required String dbFileName,
  required String encryptionKey,
}) => openConnectionImpl(dbFileName: dbFileName, encryptionKey: encryptionKey);
