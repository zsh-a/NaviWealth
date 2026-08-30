import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/product/product_metrics.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../application/knowledge_merge_proposal_applier.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

export 'knowledge_proposal_kinds.dart' show kKnowledgeProposalAppliedKinds;

const String kKnowledgeTablePrefix = 'knowledge_';

class KnowledgeProposalApplier implements ProposalApplier {
  KnowledgeProposalApplier({
    required this.repository,
    required this.ownerUserId,
    required this.stamp,
    this.onDecisionCreated,
  });

  final KnowledgeRepository repository;
  final String ownerUserId;
  final Future<SyncMeta> Function() stamp;
  final Future<void> Function()? onDecisionCreated;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      return switch (plan.kind) {
        'knowledge_capture' => await _applyCapture(plan),
        'knowledge_merge' => await KnowledgeMergeProposalApplier(
          repository: repository,
          ownerUserId: ownerUserId,
          stamp: stamp,
        ).apply(plan),
        _ => throw ProposalApplyException(
          'unknown knowledge proposal kind: ${plan.kind}',
        ),
      };
    } on ProposalApplyException {
      rethrow;
    } catch (error) {
      throw ProposalApplyException(error.toString());
    }
  }

  Future<ProposalApplyState> _applyCapture(ReadyProposalPlan plan) async {
    final type = plan.get('entity_type');
    final title = plan.get('title')?.trim() ?? '';
    final body = plan.get('body')?.trim() ?? '';
    if (title.isEmpty) throw ProposalApplyException('capture 缺少 title');
    final sync = await stamp();
    final id = kKnowledgeUuid.v4();
    if (type == 'note') {
      final tags = plan.payload['tags'] is List
          ? (plan.payload['tags'] as List<Object?>).whereType<String>().toList(
              growable: false,
            )
          : const <String>[];
      await repository.upsertNote(
        KnowledgeNote(
          id: id,
          title: title,
          bodyMd: body,
          sourceUrl: plan.get('source_url'),
          tags: tags,
          createdAt: sync.updatedAt,
          sync: sync,
        ),
      );
      return _createdState(id, 'knowledge_notes', '已保存笔记：$title');
    }
    if (type == 'decision') {
      final selected = plan.get('selected_label')?.trim() ?? '';
      final options = canonicalizeDecisionOptions(
        _maps(plan.payload['options']).map(DecisionOption.fromJson),
      );
      if (!hasValidDecisionOptions(
        options,
        selectedLabel: selected,
        maxOptions: 3,
      )) {
        throw ProposalApplyException('Decision options / selected_label 无效');
      }
      await repository.upsertDecision(
        KnowledgeDecision(
          id: id,
          question: title,
          options: options,
          selectedLabel: selected,
          rationaleMd: body,
          status: DecisionStatus.active,
          decidedAt: sync.updatedAt,
          sync: sync,
        ),
      );
      try {
        await onDecisionCreated?.call();
      } on Object {
        // Product evidence is best-effort and must not invalidate a confirmed
        // domain write.
      }
      return _createdState(id, 'knowledge_decisions', '已记录决策：$title');
    }
    throw ProposalApplyException('capture 只支持 note / decision');
  }

  ProposalApplyState _createdState(String id, String table, String label) {
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: id,
      appliedTable: table,
      appliedAt: DateTime.now().toUtc(),
      undoData: <String, Object?>{
        'delete': <Object?>[
          <String, Object?>{'table': table, 'id': id},
        ],
      },
      shortLabel: label,
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    if (state.status != ProposalApplyStatus.applied) return;
    final data = state.undoData;
    if (data == null) throw ProposalApplyException('KnowledgeOS undo 缺失');
    final restore = data['restore'];
    if (restore is List) {
      for (final raw in restore.whereType<Map<Object?, Object?>>()) {
        await _restore(raw.map((key, value) => MapEntry('$key', value)));
      }
    }
    final delete = data['delete'];
    if (delete is List) {
      for (final raw in delete.whereType<Map<Object?, Object?>>()) {
        final row = raw.map((key, value) => MapEntry('$key', value));
        final kind = switch (row['table']) {
          'knowledge_notes' => KnowledgeEntryKind.note,
          'knowledge_decisions' => KnowledgeEntryKind.decision,
          _ => null,
        };
        final id = row['id'];
        if (kind == null || id is! String) continue;
        final sync = await stamp();
        await repository.deleteEntry(
          kind: kind,
          id: id,
          sync: sync.copyWith(deletedAt: sync.updatedAt),
        );
      }
    }
  }

  Future<void> _restore(Map<String, Object?> row) async {
    final sync = await stamp();
    if (row['entity_type'] == 'note') {
      await repository.upsertNote(
        KnowledgeNote(
          id: row['id'] as String,
          title: row['title'] as String? ?? '',
          bodyMd: row['body'] as String? ?? '',
          sourceUrl: row['source_url'] as String?,
          tags: _strings(row['tags']),
          createdAt: _date(row['created_at']) ?? sync.updatedAt,
          mergedIntoId: row['merged_into_id'] as String?,
          sync: sync,
        ),
      );
      return;
    }
    if (row['entity_type'] == 'decision') {
      await repository.upsertDecision(
        KnowledgeDecision(
          id: row['id'] as String,
          question: row['question'] as String? ?? '',
          options: _maps(row['options']).map(DecisionOption.fromJson).toList(),
          selectedLabel: row['selected_label'] as String? ?? '',
          rationaleMd: row['rationale'] as String? ?? '',
          expectedOutcome: row['expected_outcome'] as String?,
          reviewDate: _date(row['review_date']),
          revisitConditions: _maps(row['revisit_conditions'])
              .map(DecisionRevisitCondition.fromJson)
              .toList(),
          actualOutcomeMd: row['actual_outcome'] as String?,
          status: DecisionStatus.parse(row['status'] as String? ?? 'active'),
          supersededByDecisionId: row['superseded_by'] as String?,
          decidedAt: _date(row['decided_at']) ?? sync.updatedAt,
          mergedIntoId: row['merged_into_id'] as String?,
          sync: sync,
        ),
      );
    }
  }
}

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

List<Map<String, Object?>> _maps(Object? value) => value is List
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((row) => row.map((key, value) => MapEntry('$key', value)))
          .toList(growable: false)
    : const <Map<String, Object?>>[];

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

final knowledgeProposalApplierProvider =
    FutureProvider<KnowledgeProposalApplier>((ref) async {
      final stamper = await ref.watch(mutationStamperProvider.future);
      return KnowledgeProposalApplier(
        repository: await ref.watch(knowledgeRepositoryProvider.future),
        ownerUserId: await ref.watch(currentUserIdProvider)(),
        stamp: () async {
          final value = await stamper.stamp();
          return SyncMeta(
            ownerUserId: value.ownerUserId,
            updatedAt: value.now,
            updatedByDevice: value.deviceId,
            hlc: value.hlc,
          );
        },
        onDecisionCreated: () => recordProductMetric(
          () => ref.read(productMetricsProvider.notifier),
          ProductFunnelEvent.knowledgeDecisionCreated,
          success: true,
        ),
      );
    });
