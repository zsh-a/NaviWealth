import 'package:drift/drift.dart';

import 'connection_stub.dart'
    if (dart.library.io) 'connection_native.dart'
    if (dart.library.html) 'connection_web.dart';

/// Opens a [QueryExecutor] for [AppDatabase].
QueryExecutor openAppConnection({
  required String dbFileName,
}) => openConnectionImpl(dbFileName: dbFileName);
