/// Ingest-owned LLM completion seam.
///
/// App bootstrap injects an FRB-backed implementation when a native LLM
/// profile is available. Ingest code depends on this feature contract instead
/// of importing app-level FRB runtime providers directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class IngestLlmProfileClient {
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  });
}

final ingestLlmProfileClientProvider = Provider<IngestLlmProfileClient?>(
  (ref) => null,
);
