/// Dart-side streaming adapter for the FRB agent runtime LLM surface.
///
/// The native API intentionally streams primitive JSON strings. This adapter
/// keeps that generated shape out of app code by decoding each event into a
/// map while reusing [AgentRuntimeLlmBridge] for active-profile request
/// construction.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_storage_policy.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/core/native/lifeos_native_runtime.dart';
import 'package:naviwealth/src/rust/api/agent_runtime.dart' as rust;

typedef AgentRuntimeChatTurnJsonStream = Stream<String> Function({
  required String requestJson,
});

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
        storagePolicy: ref.watch(agentRuntimeStoragePolicyProvider),
      );
    });

class AgentRuntimeLlmStreamBridge {
  AgentRuntimeLlmStreamBridge({
    required AgentRuntimeLlmBridge llmBridge,
    required LifeosNativeRuntimeInitializer initRuntime,
    String? libraryPath,
    AgentRuntimeStoragePolicy storagePolicy =
        const AgentRuntimeStoragePolicy.appOwned(),
    AgentRuntimeChatTurnJsonStream? streamChatTurnJson,
    Future<String> Function()? prepareChatStream,
    Future<void> Function(String)? cancelChatStream,
  }) : _llmBridge = llmBridge,
       _initRuntime = initRuntime,
       _libraryPath = libraryPath,
       _storagePolicy = storagePolicy,
       _streamChatTurnJson =
           streamChatTurnJson ?? rust.agentRuntimeStreamChatTurn,
       _prepareChatStream =
           prepareChatStream ??
           (streamChatTurnJson == null
               ? rust.agentRuntimePrepareChatStream
               : () async => ''),
       _cancelChatStream =
           cancelChatStream ??
           (streamChatTurnJson == null
               ? ((id) => rust.agentRuntimeCancelChatStream(streamId: id))
               : (_) async {});

  final AgentRuntimeLlmBridge _llmBridge;
  final LifeosNativeRuntimeInitializer _initRuntime;
  final String? _libraryPath;
  final AgentRuntimeStoragePolicy _storagePolicy;
  final AgentRuntimeChatTurnJsonStream _streamChatTurnJson;
  final Future<String> Function() _prepareChatStream;
  final Future<void> Function(String) _cancelChatStream;

  Future<void>? _initFuture;

  Stream<Map<String, Object?>> streamChatTurn({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    List<Map<String, Object?>> contextBlocks = const <Map<String, Object?>>[],
    Map<String, Object?>? contextPolicy,
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
    Map<String, Object?>? interactionResponse,
    Map<String, Object?>? suspendInteraction,
  }) async* {
    await _ensureInitialized();
    final request = _buildChatTurnRequest(
      messages: messages,
      tools: tools,
      contextBlocks: contextBlocks,
      contextPolicy: contextPolicy,
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
      interactionResponse: interactionResponse,
      suspendInteraction: suspendInteraction,
    );
    try {
      await for (final eventJson in _managedChatStream(request)) {
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

  /// Keep the native receive port alive until Rust has dropped its request.
  /// Merely cancelling the generated Dart subscription cannot stop native I/O.
  Stream<String> _managedChatStream(Map<String, Object?> request) {
    late final StreamController<String> controller;
    StreamSubscription<String>? subscription;
    final finished = Completer<void>();
    String? id;
    Future<void>? cancellation;
    var cancelled = false;
    Future<void> cancelNative() {
      final streamId = id;
      if (streamId == null || streamId.isEmpty) return Future<void>.value();
      return cancellation ??=
          Future<void>.sync(() => _cancelChatStream(streamId))
              .timeout(const Duration(seconds: 5))
              .catchError((Object error, StackTrace stack) {
                developer.log(
                  'Native chat cancellation failed',
                  name: 'agent_runtime',
                  error: error,
                  stackTrace: stack,
                );
              });
    }

    void finish() {
      if (!finished.isCompleted) finished.complete();
    }

    Future<void> start() async {
      try {
        id = await _prepareChatStream();
        if (cancelled) {
          await cancelNative();
          finish();
          return;
        }
        final metadata = Map<String, Object?>.from(request['metadata'] as Map);
        if (id!.isNotEmpty) metadata['native_stream_id'] = id;
        subscription =
            _streamChatTurnJson(
              requestJson: jsonEncode({...request, 'metadata': metadata}),
            ).listen(
              (event) {
                if (!cancelled) controller.add(event);
              },
              onError: (Object error, StackTrace stack) {
                if (!cancelled) controller.addError(error, stack);
              },
              onDone: () {
                finish();
                unawaited(controller.close());
              },
            );
      } catch (error, stack) {
        if (!cancelled) controller.addError(error, stack);
        await cancelNative();
        finish();
        unawaited(controller.close());
      }
    }

    controller = StreamController<String>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        cancelled = true;
        if (id == '') {
          await subscription?.cancel();
          finish();
          return;
        }
        if (!finished.isCompleted && id != null) {
          await cancelNative();
        }
        // Bound cleanup if a broken/older native binary cannot acknowledge.
        try {
          await finished.future.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          /* The native-side cancellation was still sent. */
        }
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> _ensureInitialized() {
    _storagePolicy.requireAppOwned(surface: 'agent-runtime stream bridge');
    return _initFuture ??= _initRuntime(libraryPath: _libraryPath);
  }

  Map<String, Object?> _buildChatTurnRequest({
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
    required List<Map<String, Object?>> contextBlocks,
    required Map<String, Object?>? contextPolicy,
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
    required Map<String, Object?>? interactionResponse,
    required Map<String, Object?>? suspendInteraction,
  }) {
    final runtimeMetadata = <String, Object?>{
      ...metadata,
      'chat_state': ?chatState,
      if (toolResults.isNotEmpty) 'tool_results': toolResults,
      'interaction_response': ?interactionResponse,
      'suspend_interaction': ?suspendInteraction,
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
      if (contextBlocks.isNotEmpty) 'context_blocks': contextBlocks,
      'context_policy': ?contextPolicy,
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
