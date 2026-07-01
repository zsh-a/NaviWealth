/// FRB-backed profile-completion adapters used by app-level provider wiring.
library;

import '../../core/ai/contracts/contracts.dart';
import '../../features/activity/data/activity_entry_insight_client.dart';
import '../../features/ingest/data/ingest_llm_client.dart';
import '../../features/knowledge/data/knowledge_llm_client.dart';
import '../../l10n/gen/app_localizations.dart';
import 'agent_runtime_llm_bridge.dart';

class FrbActivityEntryInsightClient implements ActivityEntryInsightClient {
  FrbActivityEntryInsightClient({
    required AgentRuntimeLlmBridge llmBridge,
    FrbProfileCompletionTraceRecorder? recordTrace,
  }) : _completer = _TracedProfileCompleter(
         llmBridge: llmBridge,
         recordTrace: recordTrace,
         domain: 'finance',
         defaultAgentId: 'finance_activity_insight',
       );

  final _TracedProfileCompleter _completer;

  @override
  Future<String?> explain(
    ActivityEntryInsightRequest request,
    AppLocalizations l10n,
  ) async {
    const agentId = 'finance_activity_insight';
    const surface = 'finance_activity_insight';
    final response = await _completer.completeProfile(
      messages: <Map<String, Object?>>[
        <String, Object?>{
          'role': 'system',
          'content': activityEntryInsightSystem(request.locale),
        },
        <String, Object?>{
          'role': 'user',
          'content': activityEntryInsightPrompt(request, l10n),
        },
      ],
      maxOutputTokens: 256,
      metadata: const <String, Object?>{
        'surface': surface,
        'agent_id': agentId,
      },
    );
    final body = response['content'];
    return body is String ? body : null;
  }
}

typedef FrbProfileCompletionTraceRecorder =
    Future<Object?> Function({
      required String agentId,
      required Map<String, Object?>? llmResponse,
      DateTime? startedAt,
      DateTime? finishedAt,
      String? requestId,
      String domain,
      String surface,
      String routingReason,
      Object? error,
    });

Future<void> _recordProfileCompletionBestEffort(
  FrbProfileCompletionTraceRecorder? recordTrace, {
  required String agentId,
  required Map<String, Object?>? llmResponse,
  DateTime? startedAt,
  DateTime? finishedAt,
  String? requestId,
  required String domain,
  required String surface,
  String routingReason = kFrbAgentRuntimeProfileRoutingReason,
  Object? error,
}) async {
  if (recordTrace == null) return;
  try {
    await recordTrace(
      agentId: agentId,
      llmResponse: llmResponse,
      startedAt: startedAt,
      finishedAt: finishedAt,
      requestId: requestId,
      domain: domain,
      surface: surface,
      routingReason: routingReason,
      error: error,
    );
  } catch (_) {
    // Local transparency capture must not change the FRB business result.
  }
}

class _TracedProfileCompleter {
  const _TracedProfileCompleter({
    required AgentRuntimeLlmBridge llmBridge,
    required String domain,
    required String defaultAgentId,
    FrbProfileCompletionTraceRecorder? recordTrace,
    String routingReason = kFrbAgentRuntimeProfileRoutingReason,
  }) : _llmBridge = llmBridge,
       _recordTrace = recordTrace,
       _domain = domain,
       _defaultAgentId = defaultAgentId,
       _routingReason = routingReason;

  final AgentRuntimeLlmBridge _llmBridge;
  final FrbProfileCompletionTraceRecorder? _recordTrace;
  final String _domain;
  final String _defaultAgentId;
  final String _routingReason;

  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final startedAt = DateTime.now().toUtc();
    final agentId = _metadataString(metadata, 'agent_id') ?? _defaultAgentId;
    final surface = _metadataString(metadata, 'surface') ?? agentId;
    try {
      final response = await _llmBridge.completeProfile(
        messages: messages,
        tools: tools,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        metadata: metadata,
      );
      await _recordProfileCompletionBestEffort(
        _recordTrace,
        agentId: agentId,
        llmResponse: response,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        domain: _domain,
        surface: surface,
        routingReason: _routingReason,
      );
      return response;
    } on Object catch (error) {
      await _recordProfileCompletionBestEffort(
        _recordTrace,
        agentId: agentId,
        llmResponse: null,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        domain: _domain,
        surface: surface,
        routingReason: _routingReason,
        error: error,
      );
      rethrow;
    }
  }
}

class FrbKnowledgeLlmProfileClient implements KnowledgeLlmProfileClient {
  FrbKnowledgeLlmProfileClient({
    required AgentRuntimeLlmBridge llmBridge,
    FrbProfileCompletionTraceRecorder? recordTrace,
  }) : _completer = _TracedProfileCompleter(
         llmBridge: llmBridge,
         recordTrace: recordTrace,
         domain: 'knowledge',
         defaultAgentId: 'knowledge_llm',
       );

  final _TracedProfileCompleter _completer;

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    return _completer.completeProfile(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
    );
  }
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

class FrbIngestLlmProfileClient implements IngestLlmProfileClient {
  FrbIngestLlmProfileClient({
    required AgentRuntimeLlmBridge llmBridge,
    FrbProfileCompletionTraceRecorder? recordTrace,
  }) : _completer = _TracedProfileCompleter(
         llmBridge: llmBridge,
         recordTrace: recordTrace,
         domain: 'finance',
         defaultAgentId: 'finance_ingest',
         routingReason: kFrbVisionIngestRoutingReason,
       );

  final _TracedProfileCompleter _completer;

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    return _completer.completeProfile(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: metadata,
    );
  }
}
