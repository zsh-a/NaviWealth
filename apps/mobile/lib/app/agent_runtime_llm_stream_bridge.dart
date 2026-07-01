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
import 'agent_runtime_json.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_native_bridge.dart';

typedef AgentRuntimeChatTurnJsonStream =
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
    AgentRuntimeChatTurnJsonStream? streamChatTurnJson,
  }) : _llmBridge = llmBridge,
       _initRuntime = initRuntime,
       _libraryPath = libraryPath,
       _streamChatTurnJson =
           streamChatTurnJson ?? rust.agentRuntimeStreamChatTurn;

  final AgentRuntimeLlmBridge _llmBridge;
  final LifeosNativeRuntimeInitializer _initRuntime;
  final String? _libraryPath;
  final AgentRuntimeChatTurnJsonStream _streamChatTurnJson;

  Future<void>? _initFuture;

  Stream<Map<String, Object?>> streamChatTurn({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
    String? turnId,
    String? sessionId,
    String? threadId,
    String? surface,
    String? agentId,
    String? mode,
    int? maxToolRounds,
    Map<String, Object?>? chatState,
    List<Map<String, Object?>> toolResults = const <Map<String, Object?>>[],
  }) async* {
    await _ensureInitialized();
    final request = _buildChatTurnRequest(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
      turnId: turnId,
      sessionId: sessionId,
      threadId: threadId,
      surface: surface,
      agentId: agentId,
      mode: mode,
      maxToolRounds: maxToolRounds,
      chatState: chatState,
      toolResults: toolResults,
    );
    try {
      await for (final eventJson in _streamChatTurnJson(
        requestJson: jsonEncode(request),
      )) {
        yield agentRuntimeDecodeObject(
          eventJson,
          label: 'agent runtime LLM stream event',
        );
      }
    } on FormatException {
      rethrow;
    } catch (error) {
      yield _streamErrorEvent(error);
    }
  }

  Future<void> _ensureInitialized() {
    return _initFuture ??= _initRuntime(libraryPath: _libraryPath);
  }

  Map<String, Object?> _buildChatTurnRequest({
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
    required Map<String, Object?> metadata,
    required double? temperature,
    required int? maxOutputTokens,
    required String? turnId,
    required String? sessionId,
    required String? threadId,
    required String? surface,
    required String? agentId,
    required String? mode,
    required int? maxToolRounds,
    required Map<String, Object?>? chatState,
    required List<Map<String, Object?>> toolResults,
  }) {
    final runtimeMetadata = <String, Object?>{
      ...metadata,
      'chat_state': ?chatState,
      if (toolResults.isNotEmpty) 'tool_results': toolResults,
    };
    final llmRequest = _llmBridge.buildRequest(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: runtimeMetadata,
    );
    return <String, Object?>{
      'protocol_version': llmRequest['protocol_version'],
      'turn_id': ?turnId,
      'session_id': ?sessionId,
      'thread_id': ?threadId,
      'surface': ?surface,
      'agent_id': ?agentId,
      'mode': ?mode,
      'provider': llmRequest['provider'],
      'model': llmRequest['model'],
      'messages': llmRequest['messages'],
      'temperature': ?llmRequest['temperature'],
      'max_output_tokens': ?llmRequest['max_output_tokens'],
      'tools': llmRequest['tools'],
      'metadata': llmRequest['metadata'],
      'max_tool_rounds': ?maxToolRounds,
    };
  }
}

Map<String, Object?> _streamErrorEvent(Object error) {
  return <String, Object?>{
    'kind': 'error',
    'content': null,
    'metadata': <String, Object?>{
      'code': 'frb_llm_stream_error',
      'message': error.toString(),
      'retryable': false,
      'details': const <String, Object?>{},
    },
  };
}
