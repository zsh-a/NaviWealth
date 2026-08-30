/// FRB-backed profile-completion adapters used by app-level provider wiring.
library;

import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/features/finance/activity/data/activity_entry_insight_client.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_llm_client.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_rewrite_client.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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

class FrbKnowledgeRewriteClient implements KnowledgeRewriteClient {
  FrbKnowledgeRewriteClient({
    required AgentRuntimeLlmBridge llmBridge,
    FrbProfileCompletionTraceRecorder? recordTrace,
  }) : _completer = _TracedProfileCompleter(
         llmBridge: llmBridge,
         recordTrace: recordTrace,
         domain: 'knowledge',
         defaultAgentId: 'knowledge_rewrite',
       );

  final _TracedProfileCompleter _completer;

  @override
  Future<KnowledgeRewriteDraft> rewrite(KnowledgeRewriteRequest request) async {
    const agentId = 'knowledge_rewrite';
    const surface = 'knowledge_rewrite';
    try {
      return await _completer.completeProfileAndTransform(
        messages: <Map<String, Object?>>[
          <String, Object?>{
            'role': 'system',
            'content': knowledgeRewriteSystemPrompt(request),
          },
          <String, Object?>{
            'role': 'user',
            'content': knowledgeRewriteUserPrompt(request),
          },
        ],
        temperature: 0,
        maxOutputTokens: 8192,
        responseFormat: const <String, Object?>{'type': 'json_object'},
        metadata: <String, Object?>{
          'surface': surface,
          'agent_id': agentId,
          'object_type': request.kind.wire,
          'object_id': request.objectId,
          'rewrite_style': request.style.wire,
        },
        transform: (response) => _parseKnowledgeRewriteResponse(
          request: request,
          response: response,
        ),
      );
    } on Object catch (error, stackTrace) {
      final message = error.toString();
      if (message.contains('structured_output_parse_failed')) {
        final mapped =
            message.contains('EOF') || message.contains('line 1 column 0')
            ? const KnowledgeRewriteEmptyResponseException()
            : const FormatException('Rewrite response is not valid JSON.');
        Error.throwWithStackTrace(mapped, stackTrace);
      }
      if (message.contains('structured_output_not_object') ||
          message.contains('structured_output_schema_validation_failed')) {
        Error.throwWithStackTrace(
          const FormatException('Rewrite response has an invalid structure.'),
          stackTrace,
        );
      }
      rethrow;
    }
  }
}

KnowledgeRewriteDraft _parseKnowledgeRewriteResponse({
  required KnowledgeRewriteRequest request,
  required Map<String, Object?> response,
}) {
  final object = response['object'];
  if (object is Map<String, Object?>) {
    final draft = parseKnowledgeRewriteObject(
      kind: request.kind,
      value: object,
    );
    return validateKnowledgeRewriteDraft(request: request, draft: draft);
  }
  final content = response['content'];
  if (content is! String || content.trim().isEmpty) {
    throw KnowledgeRewriteEmptyResponseException(
      finishReason: response['finish_reason'] as String?,
    );
  }
  final draft = parseKnowledgeRewriteDraft(
    kind: request.kind,
    response: content,
  );
  return validateKnowledgeRewriteDraft(request: request, draft: draft);
}

typedef FrbProfileCompletionTraceRecorder = Future<Object?> Function({
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
    Map<String, Object?>? responseFormat,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => completeProfileAndTransform(
    messages: messages,
    tools: tools,
    temperature: temperature,
    maxOutputTokens: maxOutputTokens,
    responseFormat: responseFormat,
    metadata: metadata,
    transform: (response) => response,
  );

  Future<T> completeProfileAndTransform<T>({
    required List<Map<String, Object?>> messages,
    required T Function(Map<String, Object?> response) transform,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?>? responseFormat,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final startedAt = DateTime.now().toUtc();
    final agentId = _metadataString(metadata, 'agent_id') ?? _defaultAgentId;
    final surface = _metadataString(metadata, 'surface') ?? agentId;
    Map<String, Object?>? response;
    try {
      response = await _llmBridge.completeProfile(
        messages: messages,
        tools: tools,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        responseFormat: responseFormat,
        metadata: metadata,
      );
      final result = transform(response);
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
      return result;
    } on Object catch (error) {
      await _recordProfileCompletionBestEffort(
        _recordTrace,
        agentId: agentId,
        llmResponse: response,
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
