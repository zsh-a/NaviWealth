import 'package:drift/drift.dart';

QueryExecutor openConnectionImpl({
  required String dbFileName,
  required String encryptionKey,
}) {
  throw UnsupportedError('No platform connection available for current target');
}
