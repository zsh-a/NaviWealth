import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../data/execution_repository.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';

export 'execution_proposal_kinds.dart' show kExecutionProposalAppliedKinds;

const String kExecutionTablePrefix = 'execution_';

class ExecutionProposalApplier implements ProposalApplier {
  ExecutionProposalApplier({
    required this.ref,
    required this.ownerUserId,
    required this.stamp,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final Ref ref;
  final String ownerUserId;
  final Future<SyncMeta> Function() stamp;
  final DateTime Function() _now;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      return switch (plan.kind) {
        'execution_action' => await _applyAction(plan),
        'execution_action_status_update' => await _applyActionStatusUpdate(
          plan,
        ),
        'execution_plan' => await _applyPlan(plan),
        'execution_progress' => await _applyProgress(plan),
        _ => throw ProposalApplyException(
          'unknown execution proposal kind: ${plan.kind}',
        ),
      };
    } on ProposalApplyException {
      rethrow;
    } catch (e) {
      throw ProposalApplyException(e.toString());
    }
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    if (state.status != ProposalApplyStatus.applied) return;
    final rowId = state.appliedEntityId;
    final table = state.appliedTable;
    if (rowId == null || table == null) {
      throw ProposalApplyException('ExecutionOS undo data missing');
    }
    final repo = await ref.read(executionRepositoryProvider.future);
    final meta = await stamp();
    final tombstone = meta.copyWith(deletedAt: meta.updatedAt);
    switch (table) {
      case 'execution_actions':
        if (state.undoData?['kind'] == 'action_status_update') {
          await _undoActionStatusUpdate(state, meta);
          return;
        }
        final existing = await repo.findAction(
          ownerUserId: ownerUserId,
          id: rowId,
        );
        if (existing == null) return;
        await repo.upsertAction(existing.copyWith(sync: tombstone));
      case 'execution_plans':
        final existing = await repo.findPlan(
          ownerUserId: ownerUserId,
          id: rowId,
        );
        if (existing == null) return;
        await repo.upsertPlan(
          ExecutionPlan(
            id: existing.id,
            title: existing.title,
            description: existing.description,
            status: existing.status,
            horizon: existing.horizon,
            targetDate: existing.targetDate,
            source: existing.source,
            createdAt: existing.createdAt,
            completedAt: existing.completedAt,
            sync: tombstone,
          ),
        );
      case 'execution_progress_entries':
        final existing = await repo.findProgress(
          ownerUserId: ownerUserId,
          id: rowId,
        );
        if (existing == null) return;
        await repo.upsertProgress(
          ExecutionProgressEntry(
            id: existing.id,
            actionId: existing.actionId,
            planId: existing.planId,
            kind: existing.kind,
            note: existing.note,
            createdAt: existing.createdAt,
            sync: tombstone,
          ),
        );
      default:
        throw ProposalApplyException('unknown execution undo table: $table');
    }
  }

  Future<ProposalApplyState> _applyAction(ReadyProposalPlan plan) async {
    final title = _require(plan, 'title');
    final meta = await stamp();
    final repo = await ref.read(executionRepositoryProvider.future);
    final source = _sourceRef(plan);
    final planId = await _validatedPlanId(repo, plan.get('plan_id'));
    final openActions = await repo.listOpenActions(
      ownerUserId: ownerUserId,
      limit: 500,
    );
    for (final existing in openActions) {
      if (!_sameConcreteSource(existing.source, source)) continue;
      if (_titleSimilarity(existing.title, title) < 0.85) continue;
      throw ProposalApplyException(
        'similar open action already exists: ${existing.id}',
      );
    }
    final action = ExecutionAction(
      id: kExecutionUuid.v4(),
      title: title,
      note: plan.get('note') ?? '',
      priority: ExecutionPriority.parse(plan.get('priority') ?? 'normal'),
      dueAt: _parseOptionalUtc(plan.get('due_at')),
      scheduledFor: _parseOptionalUtc(plan.get('scheduled_for')),
      planId: planId,
      source: source,
      createdAt: meta.updatedAt,
      sync: meta,
    );
    await repo.upsertAction(action);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: action.id,
      appliedTable: 'execution_actions',
      appliedAt: _now(),
      shortLabel: '已创建 Action：${action.title}',
    );
  }

  bool _sameConcreteSource(ExecutionSourceRef a, ExecutionSourceRef b) {
    if (a.isEmpty || b.isEmpty) return false;
    return a.domain == b.domain &&
        a.rowFamily == b.rowFamily &&
        a.rowId == b.rowId;
  }

  double _titleSimilarity(String a, String b) {
    Set<String> tokens(String value) => value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'))
        .where((part) => part.isNotEmpty)
        .toSet();
    final left = tokens(a);
    final right = tokens(b);
    if (left.isEmpty || right.isEmpty) {
      return a.trim().toLowerCase() == b.trim().toLowerCase() ? 1 : 0;
    }
    final intersection = left.where(right.contains).length;
    final union = <String>{...left, ...right}.length;
    return intersection / union;
  }

  Future<ProposalApplyState> _applyActionStatusUpdate(
    ReadyProposalPlan plan,
  ) async {
    final actionId = _require(plan, 'action_id');
    final status = ExecutionActionStatus.parse(_require(plan, 'status'));
    final repo = await ref.read(executionRepositoryProvider.future);
    final action = await repo.findAction(
      ownerUserId: ownerUserId,
      id: actionId,
    );
    if (action == null) {
      throw ProposalApplyException('execution action not found: $actionId');
    }

    final progressNote = plan.get('progress_note');
    final progressId = progressNote == null || progressNote.trim().isEmpty
        ? null
        : kExecutionUuid.v4();
    final meta = await stamp();
    await repo.updateActionStatus(
      action: action,
      status: status,
      sync: meta,
      progressId: progressId,
      progressNote: progressNote,
    );
    final undoData = <String, Object?>{
      'kind': 'action_status_update',
      'previous_status': action.status.wire,
      if (action.completedAt != null)
        'previous_completed_at': action.completedAt!.toUtc().toIso8601String(),
    };
    if (progressId != null) undoData['progress_id'] = progressId;
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: action.id,
      appliedTable: 'execution_actions',
      appliedAt: _now(),
      undoData: undoData,
      shortLabel: '已更新 Action 状态：${action.title}',
    );
  }

  Future<ProposalApplyState> _applyPlan(ReadyProposalPlan plan) async {
    final title = _require(plan, 'title');
    final meta = await stamp();
    final repo = await ref.read(executionRepositoryProvider.future);
    final executionPlan = ExecutionPlan(
      id: kExecutionUuid.v4(),
      title: title,
      description: plan.get('description') ?? '',
      horizon: ExecutionHorizon.parse(plan.get('horizon') ?? 'open'),
      targetDate: _parseOptionalUtc(plan.get('target_date')),
      source: _sourceRef(plan),
      createdAt: meta.updatedAt,
      sync: meta,
    );
    await repo.upsertPlan(executionPlan);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: executionPlan.id,
      appliedTable: 'execution_plans',
      appliedAt: _now(),
      shortLabel: '已创建计划：${executionPlan.title}',
    );
  }

  Future<ProposalApplyState> _applyProgress(ReadyProposalPlan plan) async {
    final note = _require(plan, 'note');
    final meta = await stamp();
    final repo = await ref.read(executionRepositoryProvider.future);
    final actionId = plan.get('action_id');
    ExecutionAction? action;
    if (actionId != null) {
      action = await repo.findAction(ownerUserId: ownerUserId, id: actionId);
      if (action == null) {
        throw ProposalApplyException('execution action not found: $actionId');
      }
    }
    final planId = await _validatedPlanId(
      repo,
      plan.get('plan_id') ?? action?.planId,
    );
    final progress = ExecutionProgressEntry(
      id: kExecutionUuid.v4(),
      actionId: actionId,
      planId: planId,
      kind: ExecutionProgressKind.parse(plan.get('kind') ?? 'checkin'),
      note: note,
      createdAt: meta.updatedAt,
      sync: meta,
    );
    await repo.upsertProgress(progress);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: progress.id,
      appliedTable: 'execution_progress_entries',
      appliedAt: _now(),
      shortLabel: '已记录更新',
    );
  }

  Future<String?> _validatedPlanId(
    ExecutionRepository repo,
    String? planId,
  ) async {
    if (planId != null && planId.isNotEmpty) {
      final executionPlan = await repo.findPlan(
        ownerUserId: ownerUserId,
        id: planId,
      );
      if (executionPlan == null) {
        throw ProposalApplyException('execution plan not found: $planId');
      }
    }
    return planId;
  }

  Future<void> _undoActionStatusUpdate(
    ProposalApplyState state,
    SyncMeta meta,
  ) async {
    final rowId = state.appliedEntityId;
    if (rowId == null) {
      throw ProposalApplyException(
        'ExecutionOS action status undo row missing',
      );
    }
    final undoData = state.undoData ?? const <String, Object?>{};
    final previousStatus = ExecutionActionStatus.parse(
      undoData['previous_status'] as String? ?? ExecutionActionStatus.todo.wire,
    );
    final previousCompletedAt = _parseOptionalUtc(
      undoData['previous_completed_at'] as String?,
    );
    final repo = await ref.read(executionRepositoryProvider.future);
    final existing = await repo.findAction(ownerUserId: ownerUserId, id: rowId);
    if (existing == null) return;
    await repo.upsertAction(
      ExecutionAction(
        id: existing.id,
        title: existing.title,
        note: existing.note,
        status: previousStatus,
        priority: existing.priority,
        dueAt: existing.dueAt,
        scheduledFor: existing.scheduledFor,
        planId: existing.planId,
        source: existing.source,
        createdAt: existing.createdAt,
        completedAt: previousCompletedAt,
        sync: meta,
      ),
    );

    final progressId = undoData['progress_id'] as String?;
    if (progressId == null || progressId.isEmpty) return;
    final progress = await repo.findProgress(
      ownerUserId: ownerUserId,
      id: progressId,
    );
    if (progress == null) return;
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: progress.id,
        actionId: progress.actionId,
        planId: progress.planId,
        kind: progress.kind,
        note: progress.note,
        createdAt: progress.createdAt,
        sync: meta.copyWith(deletedAt: meta.updatedAt),
      ),
    );
  }
}

String _require(ReadyProposalPlan plan, String key) {
  final value = plan.get(key);
  if (value == null) {
    throw ProposalApplyException('${plan.kind} 缺少 $key');
  }
  return value;
}

ExecutionSourceRef _sourceRef(ReadyProposalPlan plan) {
  return ExecutionSourceRef(
    domain: plan.get('source_domain'),
    rowFamily: plan.get('source_row_family'),
    rowId: plan.get('source_row_id'),
    labelSnapshot: plan.get('source_label'),
  );
}

DateTime? _parseOptionalUtc(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

final executionProposalApplierProvider =
    FutureProvider<ExecutionProposalApplier>((ref) async {
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      final stamper = await ref.watch(mutationStamperProvider.future);
      return ExecutionProposalApplier(
        ref: ref,
        ownerUserId: ownerUserId,
        stamp: () async {
          final s = await stamper.stamp();
          return SyncMeta(
            ownerUserId: s.ownerUserId,
            updatedAt: s.now,
            updatedByDevice: s.deviceId,
            hlc: s.hlc,
          );
        },
      );
    });
