import 'dart:async';

import 'package:naviwealth/core/native/lifeos_native_runtime.dart';
import 'package:naviwealth/src/rust/api/market.dart' as native;
import 'package:uuid/uuid.dart';

typedef MarketRequest = Future<String> Function(String request);

/// No AI/embedder initialization: only the shared native library is loaded.
Future<String> requestNativeMarket(String request) async {
  await initLifeosNativeRuntime();
  final id = const Uuid().v4();
  try {
    return await native
        .marketRequest(requestId: id, requestJson: request)
        .timeout(const Duration(seconds: 30));
  } on TimeoutException {
    await native.marketCancel(requestId: id);
    rethrow;
  }
}
