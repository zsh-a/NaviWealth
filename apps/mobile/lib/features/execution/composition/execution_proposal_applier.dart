import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
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
    final actionId = state.appliedEntityId;
    if (actionId == null || state.appliedTable != 'execution_actions') {
      throw ProposalApplyException('ExecutionOS undo data missing');
    }
    final repo = await ref.read(executionRepositoryProvider.future);
    final existing = await repo.findAction(
      ownerUserId: ownerUserId,
      id: actionId,
    );
    if (existing == null) return;
    final meta = await stamp();
    await repo.upsertAction(
      existing.copyWith(sync: meta.copyWith(deletedAt: meta.updatedAt)),
    );
  }

  Future<ProposalApplyState> _applyAction(ReadyProposalPlan plan) async {
    final title = plan.get('title');
    if (title == null) {
      throw ProposalApplyException('execution_action 缺少 title');
    }
    final meta = await stamp();
    final repo = await ref.read(executionRepositoryProvider.future);
    final action = ExecutionAction(
      id: kExecutionUuid.v4(),
      title: title,
      note: plan.get('note') ?? '',
      priority: ExecutionPriority.parse(plan.get('priority') ?? 'normal'),
      dueAt: _parseOptionalUtc(plan.get('due_at')),
      scheduledFor: _parseOptionalUtc(plan.get('scheduled_for')),
      commitmentId: plan.get('commitment_id'),
      source: ExecutionSourceRef(
        domain: plan.get('source_domain'),
        rowFamily: plan.get('source_row_family'),
        rowId: plan.get('source_row_id'),
        labelSnapshot: plan.get('source_label'),
      ),
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
