import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_proposal_undo.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

/// Routine proposal writer owned by the Knowledge application layer.
class KnowledgeRoutineProposalApplier {
  KnowledgeRoutineProposalApplier({
    required this.repo,
    required this.stamp,
    required this.createId,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final KnowledgeRepository repo;
  final Future<SyncMeta> Function() stamp;
  final String Function() createId;
  final DateTime Function() _now;

  Future<ProposalApplyState> applyRoutine(ReadyProposalPlan plan) async {
    return createRoutine(
      statement: _requireRoutineStatement(plan),
      intervalDays: _requireRoutineIntervalDays(plan),
      scope: plan.get('scope') ?? '*',
      nextDueAt: _parseOptionalUtc(plan.get('next_due_at')),
      summaryZh: plan.summaryZh,
    );
  }

  Future<ProposalApplyState> createRoutine({
    required String statement,
    required int intervalDays,
    required String scope,
    required DateTime? nextDueAt,
    required String summaryZh,
  }) async {
    final meta = await stamp();
    final routine = KnowledgeRoutine(
      id: createId(),
      statement: statement,
      intervalDays: intervalDays,
      nextDueAt: nextDueAt ?? meta.updatedAt.add(Duration(days: intervalDays)),
      scope: scope,
      status: RoutineStatus.active,
      createdAt: meta.updatedAt,
      sync: meta,
    );
    await repo.upsertRoutine(routine);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: routine.id,
      appliedTable: 'knowledge_routines',
      appliedAt: _now(),
      undoData: knowledgeProposalUndoData(
        delete: [knowledgeProposalDeleteRow('knowledge_routines', routine.id)],
      ),
      shortLabel: '已建立 Routine：${summaryZh.isEmpty ? statement : summaryZh}',
    );
  }
}

String _requireRoutineStatement(ReadyProposalPlan plan) {
  final statement = plan.get('statement');
  if (statement == null) {
    throw ProposalApplyException('routine 缺少 statement / interval_days');
  }
  return statement;
}

int _requireRoutineIntervalDays(ReadyProposalPlan plan) {
  final intervalDays = plan.num_('interval_days')?.toInt() ?? 0;
  if (intervalDays <= 0) {
    throw ProposalApplyException('routine 缺少 statement / interval_days');
  }
  return intervalDays;
}

DateTime? _parseOptionalUtc(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}
