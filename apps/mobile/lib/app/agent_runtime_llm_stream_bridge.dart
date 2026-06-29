/// Dart-side streaming adapter for the FRB agent runtime LLM surface.
///
/// The native API intentionally streams primitive JSON strings. This adapter
/// keeps that generated shape out of app code by decoding each event into a
/// map while reusing [AgentRuntimeLlmBridge] for active-profile request
/// construction.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/src/rust/api/agent_runtime.dart' as rust;

import '../core/ai/local/embedding/rust_gemma_embedder.dart';
import '../core/config/providers.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_native_bridge.dart';

typedef AgentRuntimeProfileLlmJsonStream =
    Stream<String> Function({required String requestJson});

final agentRuntimeLlmStreamBridgeProvider =
    Provider<AgentRuntimeLlmStreamBridge?>((ref) {
      final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
      if (llmBridge == null) return null;
      final config = ref.watch(appConfigProvider);
      return AgentRuntimeLlmStreamBridge(
        llmBridge: llmBridge,
        initRuntime: initLifeosNativeRuntime,
        libraryPath: config.rustEmbedderLibraryPath.isEmpty
            ? null
            : config.rustEmbedderLibraryPath,
      );
    });

class AgentRuntimeLlmStreamBridge {
  AgentRuntimeLlmStreamBridge({
    required AgentRuntimeLlmBridge llmBridge,
    required LifeosNativeRuntimeInitializer initRuntime,
    String? libraryPath,
    AgentRuntimeProfileLlmJsonStream streamProfileJson =
        rust.agentRuntimeStreamProfileLlm,
  }) : _llmBridge = llmBridge,
       _initRuntime = initRuntime,
       _libraryPath = libraryPath,
       _streamProfileJson = streamProfileJson;

  final AgentRuntimeLlmBridge _llmBridge;
  final LifeosNativeRuntimeInitializer _initRuntime;
  final String? _libraryPath;
  final AgentRuntimeProfileLlmJsonStream _streamProfileJson;

  Future<void>? _initFuture;

  Stream<Map<String, Object?>> streamProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async* {
    await _ensureInitialized();
    final request = _llmBridge.buildRequest(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
    );
    await for (final eventJson in _streamProfileJson(
      requestJson: jsonEncode(request),
    )) {
      yield _decodeObject(eventJson);
    }
  }

  Future<void> _ensureInitialized() {
    return _initFuture ??= _initRuntime(libraryPath: _libraryPath);
  }
}

Map<String, Object?> _decodeObject(String json) {
  final decoded = jsonDecode(json);
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('agent runtime LLM stream event is not object');
}
