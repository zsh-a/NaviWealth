/// KnowledgeOS-owned LLM completion seam.
///
/// App bootstrap injects an FRB-backed implementation when a native profile is
/// available. Knowledge data/agent code depends on this small feature contract,
/// not on app-level FRB runtime providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class KnowledgeLlmProfileClient {
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  });
}

final knowledgeLlmProfileClientProvider = Provider<KnowledgeLlmProfileClient?>(
  (ref) => null,
);
