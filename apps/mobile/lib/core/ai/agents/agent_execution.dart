import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/current_user.dart';
import '../../auth/domain_scope.dart';
import '../../auth/providers.dart' show domainOptInsProvider;
import '../../persistence/app_database.dart';
import '../../persistence/providers.dart';
import '../contracts/contracts.dart';

/// A bounded presentation projection, not a second execution engine or chat.
/// Raw tool I/O, credentials and reasoning deltas are deliberately excluded.
class AgentExecution {
  AgentExecution({
    required this.runId,
    required this.agentId,
    required this.domain,
    required this.title,
    required this.instructions,
    required this.traceId,
    required this.startedAt,
    required this.processId,
    this.status = 'running',
    this.phase = 'preparing',
    this.errorCode,
    this.summary,
    this.artifactId,
    this.finishedAt,
    List<AiSpan>? steps,
    Set<String>? activeStepIds,
  }) : steps = steps ?? [],
       activeStepIds = activeStepIds ?? {};

  final String runId, agentId, domain, title, instructions, traceId, processId;
  final DateTime startedAt;
  String status, phase;
  String? errorCode, summary, artifactId;
  DateTime? finishedAt;
  final List<AiSpan> steps;
  final Set<String> activeStepIds;
  bool get running => status == 'running';

  void record(AiSpan span, {bool running = false}) {
    // Presentation storage has a strict allowlist, even if a runtime event
    // contains raw model/tool content or provider error details.
    span = AiSpan(
      id: span.id,
      parentId: span.parentId,
      kind: span.kind,
      name: span.name,
      startOffsetMs: span.startOffsetMs,
      durationMs: span.durationMs,
      status: span.status,
      errorCode: span.errorCode,
      tokens: span.tokens,
      model: span.model,
      stopReason: span.stopReason,
    );
    final index = steps.indexWhere((step) => step.id == span.id);
    if (index < 0) {
      if (steps.length < 64) steps.add(span);
    } else {
      steps[index] = span;
    }
    if (running && steps.any((step) => step.id == span.id)) {
      activeStepIds.add(span.id);
    } else {
      activeStepIds.remove(span.id);
    }
  }

  void closeActiveSteps() {
    final elapsed = (finishedAt ?? DateTime.now().toUtc())
        .difference(startedAt)
        .inMilliseconds;
    for (final step
        in steps.where((s) => activeStepIds.contains(s.id)).toList()) {
      record(
        AiSpan(
          id: step.id,
          kind: step.kind,
          name: step.name,
          startOffsetMs: step.startOffsetMs,
          durationMs: (elapsed - step.startOffsetMs).clamp(0, elapsed),
          status: status == 'failed'
              ? AiSpanStatus.error
              : AiSpanStatus.cancelled,
          errorCode: errorCode,
        ),
      );
    }
  }

  Map<String, Object?> toJson() => {
    'run_id': runId,
    'agent_id': agentId,
    'domain': domain,
    'title': title,
    'instructions': instructions,
    'trace_id': traceId,
    'process_id': processId,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt?.toIso8601String(),
    'status': status,
    'phase': phase,
    'error_code': errorCode,
    'summary': summary,
    'artifact_id': artifactId,
    'steps': steps.map((step) => step.toJson()).toList(),
    'active_step_ids': activeStepIds.toList(),
  };

  factory AgentExecution.fromJson(Map<String, Object?> json) => AgentExecution(
    runId: json['run_id']! as String,
    agentId: json['agent_id']! as String,
    domain: json['domain']! as String,
    title: json['title']! as String,
    instructions: json['instructions']! as String,
    traceId: json['trace_id']! as String,
    processId: json['process_id']! as String,
    startedAt: DateTime.parse(json['started_at']! as String),
    finishedAt: DateTime.tryParse(json['finished_at'] as String? ?? ''),
    status: json['status']! as String,
    phase: json['phase']! as String,
    errorCode: json['error_code'] as String?,
    summary: json['summary'] as String?,
    artifactId: json['artifact_id'] as String?,
    activeStepIds: (json['active_step_ids'] as List? ?? [])
        .cast<String>()
        .toSet(),
    steps: (json['steps']! as List)
        .map((s) => AiSpan.fromJson(Map<String, Object?>.from(s as Map)))
        .toList(),
  );
}

final agentExecutionProcessId = const Uuid().v4();

/// Controls are owner-scoped and live independently of any mounted page.
class AgentExecutionControls {
  final _tokens = <(String, String), CancelToken>{};
  void register(String owner, String runId, CancelToken token) =>
      _tokens[(owner, runId)] = token;
  void unregister(String owner, String runId) => _tokens.remove((owner, runId));
  void cancel(String owner, String runId) =>
      _tokens[(owner, runId)]?.cancel('scheduled_task_user_cancelled');
  void dispose() {
    for (final token in _tokens.values) {
      token.cancel('scheduled_task_interrupted');
    }
    _tokens.clear();
  }
}

final agentExecutionControlsProvider = Provider((ref) {
  ref.watch(currentUserIdProvider);
  final controls = AgentExecutionControls();
  ref.onDispose(controls.dispose);
  return controls;
});

class AgentExecutionStore {
  const AgentExecutionStore(this.db, this.owner);
  final AppDatabase db;
  final String owner;

  Future<void> save(AgentExecution execution) => db.customStatement(
    'UPDATE agent_runs SET execution_json = ?, trace_id = ? WHERE id = ? AND owner_user_id = ?',
    [jsonEncode(execution.toJson()), execution.traceId, execution.runId, owner],
  );

  Future<AgentExecution?> read(String agentId, {String? runId}) async {
    final rows = await db
        .customSelect(
          'SELECT execution_json FROM agent_runs WHERE owner_user_id = ? AND agent_id = ? '
          '${runId == null ? '' : 'AND id = ? '}ORDER BY started_at DESC LIMIT 1',
          variables: [
            Variable(owner),
            Variable(agentId),
            if (runId != null) Variable(runId),
          ],
        )
        .get();
    final raw = rows.firstOrNull?.readNullable<String>('execution_json');
    if (raw == null) return null;
    final execution = AgentExecution.fromJson(
      jsonDecode(raw) as Map<String, Object?>,
    );
    if (execution.running && execution.processId != agentExecutionProcessId) {
      execution.status = 'interrupted';
      execution.errorCode = 'scheduled_task_interrupted';
      execution.finishedAt = DateTime.now().toUtc();
      execution.closeActiveSteps();
      await save(execution);
      await db.customStatement(
        "UPDATE agent_runs SET status = 'failed', error = ?, finished_at = ? WHERE id = ? AND owner_user_id = ? AND status = 'running'",
        [
          execution.errorCode,
          execution.finishedAt!.millisecondsSinceEpoch,
          execution.runId,
          owner,
        ],
      );
    }
    return execution;
  }
}

final agentExecutionStoreProvider = FutureProvider(
  (ref) async => AgentExecutionStore(
    await ref.watch(appDatabaseProvider.future),
    await ref.watch(currentUserIdProvider)(),
  ),
);

typedef AgentExecutionKey = ({String agentId, String? runId});

final agentExecutionProvider = StreamProvider.autoDispose
    .family<AgentExecution?, AgentExecutionKey>((ref, key) async* {
      final domains = await ref.watch(domainOptInsProvider.future);
      final store = await ref.watch(agentExecutionStoreProvider.future);
      Future<AgentExecution?> read() async {
        final execution = await store.read(key.agentId, runId: key.runId);
        final domain = execution == null
            ? null
            : DomainScope.tryParse(execution.domain);
        return domain != null && domains.contains(domain) ? execution : null;
      }

      yield await read();
      await for (final _ in Stream<void>.periodic(const Duration(seconds: 1))) {
        yield await read();
      }
    });
