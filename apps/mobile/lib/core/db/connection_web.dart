import 'package:drift/drift.dart';

QueryExecutor openConnectionImpl({
  required String dbFileName,
  required String encryptionKey,
}) {
  // Web persistence + at-rest encryption is owned by the FIR-2 web track
  // (drift wasm + IndexedDB/OPFS, browser Crypto API). Until that lands,
  // we surface a clear runtime error rather than silently storing data
  // unencrypted in an in-memory database that disappears on reload.
  return DatabaseConnection.delayed(
    Future.error(
      UnsupportedError(
        'Encrypted local storage is not yet wired up for Web. '
        'Tracking issue: FIR-2 (Web persistence track).',
      ),
    ),
  );
}
