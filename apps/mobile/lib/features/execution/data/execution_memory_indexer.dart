/// ExecutionOS object → event indexer.
///
/// Actions, Projects, and Commitments are execution state, not just UI rows.
/// This indexer mirrors their current non-deleted state into the cross-domain
/// event log so ContextBuilder can surface "what changed in execution" beside
/// Finance, Health, and Knowledge signals without core importing ExecutionOS.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/contracts/source_identity.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../domain/execution_models.dart';
import 'providers.dart';

const String kExecutionActionMemorySource = 'execution:actions';
const String kExecutionProjectMemorySource = 'execution:projects';
const String kExecutionCommitmentMemorySource = 'execution:commitments';
const String kExecutionProgressMemorySource = 'execution:progress';

const String kExecutionActionEventSourceFamily = 'exec:execution_actions';
const String kExecutionProjectEventSourceFamily = 'exec:execution_projects';
const String kExecutionCommitmentEventSourceFamily =
    'exec:execution_commitments';
const String kExecutionProgressEventSourceFamily =
    'exec:execution_progress_entries';

const String kExecutionActionEventType = 'execution_action_state';
const String kExecutionProjectEventType = 'execution_project_state';
const String kExecutionCommitmentEventType = 'execution_commitment_state';
const String kExecutionProgressEventType = 'execution_progress_recorded';

class ExecutionMemoryIndexer {
  const ExecutionMemoryIndexer();

  Future<int> reindexActions(
    MemoryRuntime runtime,
    Iterable<ExecutionAction> actions, {
    required String ownerUserId,
  }) async {
    var events = 0;
    for (final action in actions) {
      await runtime.recordEvent(_actionEvent(action, ownerUserId));
      events++;
    }
    return events;
  }

  Future<int> reindexProjects(
    MemoryRuntime runtime,
    Iterable<ExecutionProject> projects, {
    required String ownerUserId,
  }) async {
    var events = 0;
    for (final project in projects) {
      await runtime.recordEvent(_projectEvent(project, ownerUserId));
      events++;
    }
    return events;
  }

  Future<int> reindexCommitments(
    MemoryRuntime runtime,
    Iterable<ExecutionCommitment> commitments, {
    required String ownerUserId,
  }) async {
    var events = 0;
    for (final commitment in commitments) {
      await runtime.recordEvent(_commitmentEvent(commitment, ownerUserId));
      events++;
    }
    return events;
  }

  Future<int> reindexProgress(
    MemoryRuntime runtime,
    Iterable<ExecutionProgressEntry> entries, {
    required String ownerUserId,
  }) async {
    var events = 0;
    for (final entry in entries) {
      await runtime.recordEvent(_progressEvent(entry, ownerUserId));
      events++;
    }
    return events;
  }

  EventRecord _actionEvent(ExecutionAction action, String ownerUserId) {
    final dueAt = action.dueAt;
    final scheduledFor = action.scheduledFor;
    return EventRecord(
      id: '$kExecutionActionMemorySource:${action.id}',
      domain: DomainScope.execution,
      kind: EventKind.domain(DomainScope.execution, kExecutionActionEventType),
      occurredAt: action.sync.updatedAt.toUtc(),
      observedAt: action.sync.updatedAt.toUtc(),
      sourceIdentity: SourceIdentity(
        domain: DomainScope.execution,
        rowFamily: kExecutionActionEventSourceFamily,
        rowId: action.id,
        fingerprint: action.sync.hlc.toString(),
      ),
      ownerUserId: ownerUserId,
      title: 'Action ${action.status.wire}: ${action.title}',
      summary: _actionSummary(action),
      facts: <String, Object?>{
        'id': action.id,
        'title': action.title,
        'note': action.note,
        'status': action.status.wire,
        'priority': action.priority.wire,
        if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
        if (scheduledFor != null)
          'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        if (action.projectId != null) 'project_id': action.projectId,
        if (action.commitmentId != null) 'commitment_id': action.commitmentId,
        if (action.completedAt != null)
          'completed_at': action.completedAt!.toUtc().toIso8601String(),
        ..._sourcePayload(action.source),
      },
      entities: <String>{
        'execution',
        'execution_action',
        'execution_action:${action.id}',
        'status:${action.status.wire}',
        'priority:${action.priority.wire}',
        if (action.projectId != null) 'execution_project:${action.projectId}',
        if (action.commitmentId != null)
          'execution_commitment:${action.commitmentId}',
        ..._sourceEntities(action.source),
      },
      importance: _actionImportance(action),
      confidence: 1,
    );
  }

  EventRecord _projectEvent(ExecutionProject project, String ownerUserId) {
    final targetDate = project.targetDate;
    return EventRecord(
      id: '$kExecutionProjectMemorySource:${project.id}',
      domain: DomainScope.execution,
      kind: EventKind.domain(DomainScope.execution, kExecutionProjectEventType),
      occurredAt: project.sync.updatedAt.toUtc(),
      observedAt: project.sync.updatedAt.toUtc(),
      sourceIdentity: SourceIdentity(
        domain: DomainScope.execution,
        rowFamily: kExecutionProjectEventSourceFamily,
        rowId: project.id,
        fingerprint: project.sync.hlc.toString(),
      ),
      ownerUserId: ownerUserId,
      title: 'Project ${project.status.wire}: ${project.title}',
      summary: _projectSummary(project),
      facts: <String, Object?>{
        'id': project.id,
        'title': project.title,
        'description': project.description,
        'status': project.status.wire,
        'horizon': project.horizon.wire,
        if (targetDate != null)
          'target_date': targetDate.toUtc().toIso8601String(),
        if (project.completedAt != null)
          'completed_at': project.completedAt!.toUtc().toIso8601String(),
        ..._sourcePayload(project.source),
      },
      entities: <String>{
        'execution',
        'execution_project',
        'execution_project:${project.id}',
        'status:${project.status.wire}',
        'horizon:${project.horizon.wire}',
        ..._sourceEntities(project.source),
      },
      importance: _projectImportance(project),
      confidence: 1,
    );
  }

  EventRecord _commitmentEvent(
    ExecutionCommitment commitment,
    String ownerUserId,
  ) {
    final targetDate = commitment.targetDate;
    return EventRecord(
      id: '$kExecutionCommitmentMemorySource:${commitment.id}',
      domain: DomainScope.execution,
      kind: EventKind.domain(
        DomainScope.execution,
        kExecutionCommitmentEventType,
      ),
      occurredAt: commitment.sync.updatedAt.toUtc(),
      observedAt: commitment.sync.updatedAt.toUtc(),
      sourceIdentity: SourceIdentity(
        domain: DomainScope.execution,
        rowFamily: kExecutionCommitmentEventSourceFamily,
        rowId: commitment.id,
        fingerprint: commitment.sync.hlc.toString(),
      ),
      ownerUserId: ownerUserId,
      title: 'Commitment ${commitment.status.wire}: ${commitment.title}',
      summary: _commitmentSummary(commitment),
      facts: <String, Object?>{
        'id': commitment.id,
        'title': commitment.title,
        'description': commitment.description,
        'status': commitment.status.wire,
        'horizon': commitment.horizon.wire,
        if (targetDate != null)
          'target_date': targetDate.toUtc().toIso8601String(),
        if (commitment.projectId != null) 'project_id': commitment.projectId,
        if (commitment.completedAt != null)
          'completed_at': commitment.completedAt!.toUtc().toIso8601String(),
        ..._sourcePayload(commitment.source),
      },
      entities: <String>{
        'execution',
        'execution_commitment',
        'execution_commitment:${commitment.id}',
        'status:${commitment.status.wire}',
        'horizon:${commitment.horizon.wire}',
        if (commitment.projectId != null)
          'execution_project:${commitment.projectId}',
        ..._sourceEntities(commitment.source),
      },
      importance: _commitmentImportance(commitment),
      confidence: 1,
    );
  }

  EventRecord _progressEvent(ExecutionProgressEntry entry, String ownerUserId) {
    final highSignal =
        entry.kind == ExecutionProgressKind.blocker ||
        entry.kind == ExecutionProgressKind.scopeChange ||
        entry.kind == ExecutionProgressKind.completion;
    return EventRecord(
      id: '$kExecutionProgressMemorySource:${entry.id}',
      domain: DomainScope.execution,
      kind: EventKind.domain(
        DomainScope.execution,
        kExecutionProgressEventType,
      ),
      occurredAt: entry.createdAt.toUtc(),
      observedAt: entry.sync.updatedAt.toUtc(),
      sourceIdentity: SourceIdentity(
        domain: DomainScope.execution,
        rowFamily: kExecutionProgressEventSourceFamily,
        rowId: entry.id,
        fingerprint: entry.sync.hlc.toString(),
      ),
      ownerUserId: ownerUserId,
      title: 'Execution progress: ${entry.kind.wire}',
      summary: entry.note.trim().isEmpty
          ? 'Recorded ${entry.kind.wire} progress.'
          : entry.note.trim(),
      facts: <String, Object?>{
        'id': entry.id,
        'kind': entry.kind.wire,
        'note': entry.note,
        if (entry.actionId != null) 'action_id': entry.actionId,
        if (entry.projectId != null) 'project_id': entry.projectId,
        if (entry.commitmentId != null) 'commitment_id': entry.commitmentId,
      },
      entities: <String>{
        'execution',
        'execution_progress',
        'execution_progress:${entry.id}',
        'progress_kind:${entry.kind.wire}',
        if (entry.actionId != null) 'execution_action:${entry.actionId}',
        if (entry.projectId != null) 'execution_project:${entry.projectId}',
        if (entry.commitmentId != null)
          'execution_commitment:${entry.commitmentId}',
      },
      importance: highSignal ? 0.82 : 0.5,
      confidence: 1,
    );
  }
}

String _actionSummary(ExecutionAction action) {
  final parts = <String>[
    'Action "${action.title}" is ${action.status.wire}',
    'priority ${action.priority.wire}',
  ];
  if (action.dueAt != null) {
    parts.add('due ${action.dueAt!.toUtc().toIso8601String()}');
  }
  if (action.projectId != null) parts.add('project ${action.projectId}');
  if (action.commitmentId != null) {
    parts.add('commitment ${action.commitmentId}');
  }
  final source = _sourceSummary(action.source);
  if (source != null) parts.add(source);
  return '${parts.join('; ')}.';
}

String _projectSummary(ExecutionProject project) {
  final parts = <String>[
    'Project "${project.title}" is ${project.status.wire}',
    'horizon ${project.horizon.wire}',
  ];
  if (project.targetDate != null) {
    parts.add('target ${project.targetDate!.toUtc().toIso8601String()}');
  }
  final source = _sourceSummary(project.source);
  if (source != null) parts.add(source);
  return '${parts.join('; ')}.';
}

String _commitmentSummary(ExecutionCommitment commitment) {
  final parts = <String>[
    'Commitment "${commitment.title}" is ${commitment.status.wire}',
    'horizon ${commitment.horizon.wire}',
  ];
  if (commitment.targetDate != null) {
    parts.add('target ${commitment.targetDate!.toUtc().toIso8601String()}');
  }
  if (commitment.projectId != null) {
    parts.add('project ${commitment.projectId}');
  }
  final source = _sourceSummary(commitment.source);
  if (source != null) parts.add(source);
  return '${parts.join('; ')}.';
}

Map<String, Object?> _sourcePayload(ExecutionSourceRef source) {
  return <String, Object?>{
    if (source.domain != null) 'source_domain': source.domain,
    if (source.rowFamily != null) 'source_row_family': source.rowFamily,
    if (source.rowId != null) 'source_row_id': source.rowId,
    if (source.labelSnapshot != null) 'source_label': source.labelSnapshot,
  };
}

Set<String> _sourceEntities(ExecutionSourceRef source) {
  return <String>{
    if (source.domain != null) 'source_domain:${source.domain}',
    if (source.rowFamily != null) 'source_row_family:${source.rowFamily}',
    if (source.rowId != null) 'source_row:${source.rowId}',
  };
}

String? _sourceSummary(ExecutionSourceRef source) {
  if (source.isEmpty) return null;
  final label = source.labelSnapshot;
  final domain = source.domain;
  final rowFamily = source.rowFamily;
  final rowId = source.rowId;
  if (label != null && label.isNotEmpty) return 'source $label';
  final parts = <String>[
    if (domain != null && domain.isNotEmpty) domain,
    if (rowFamily != null && rowFamily.isNotEmpty) rowFamily,
    if (rowId != null && rowId.isNotEmpty) rowId,
  ];
  if (parts.isEmpty) return null;
  return 'source ${parts.join('/')}';
}

double _actionImportance(ExecutionAction action) {
  if (action.status == ExecutionActionStatus.blocked) return 0.85;
  if (action.priority == ExecutionPriority.high) return 0.78;
  if (action.status == ExecutionActionStatus.doing) return 0.72;
  if (action.status == ExecutionActionStatus.done) return 0.65;
  return 0.55;
}

double _projectImportance(ExecutionProject project) {
  return switch (project.status) {
    ExecutionProjectStatus.active => 0.72,
    ExecutionProjectStatus.paused => 0.55,
    ExecutionProjectStatus.completed => 0.68,
    ExecutionProjectStatus.archived => 0.4,
  };
}

double _commitmentImportance(ExecutionCommitment commitment) {
  return switch (commitment.status) {
    ExecutionCommitmentStatus.active => 0.78,
    ExecutionCommitmentStatus.paused => 0.58,
    ExecutionCommitmentStatus.completed => 0.7,
    ExecutionCommitmentStatus.archived => 0.42,
  };
}

final executionMemoryIndexerProvider = Provider<void>((ref) {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.execution)) return;

  const indexer = ExecutionMemoryIndexer();
  () async {
    final repo = await ref.read(executionRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final runtime = await ref.read(memoryRuntimeProvider.future);

    _subscribeExecutionIndexer<ExecutionAction>(
      ref,
      stream: repo.watchActionsForMemoryIndex(ownerUserId: userId),
      reindex: (rows) =>
          indexer.reindexActions(runtime, rows, ownerUserId: userId),
    );
    _subscribeExecutionIndexer<ExecutionProject>(
      ref,
      stream: repo.watchProjectsForMemoryIndex(ownerUserId: userId),
      reindex: (rows) =>
          indexer.reindexProjects(runtime, rows, ownerUserId: userId),
    );
    _subscribeExecutionIndexer<ExecutionCommitment>(
      ref,
      stream: repo.watchCommitmentsForMemoryIndex(ownerUserId: userId),
      reindex: (rows) =>
          indexer.reindexCommitments(runtime, rows, ownerUserId: userId),
    );
    _subscribeExecutionIndexer<ExecutionProgressEntry>(
      ref,
      stream: repo.watchProgressForMemoryIndex(ownerUserId: userId),
      reindex: (rows) =>
          indexer.reindexProgress(runtime, rows, ownerUserId: userId),
    );
  }();
});

void _subscribeExecutionIndexer<T>(
  Ref ref, {
  required Stream<List<T>> stream,
  required Future<void> Function(List<T> rows) reindex,
}) {
  var running = false;
  List<T>? pendingRows;
  final sub = stream.listen((rows) async {
    if (running) {
      pendingRows = rows;
      return;
    }
    running = true;
    try {
      var currentRows = rows;
      while (true) {
        await reindex(currentRows);
        final nextRows = pendingRows;
        pendingRows = null;
        if (nextRows == null) break;
        currentRows = nextRows;
      }
    } finally {
      running = false;
    }
  });
  ref.onDispose(sub.cancel);
}
