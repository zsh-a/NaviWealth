/// KnowledgeOS implementation of [ProposalApplier]
/// (`docs/knowledgeos-domain.md` §15.6).
///
/// Dispatches confirmed KnowledgeOS `propose_*` plans from the chat
/// propose-card to the matching `KnowledgeRepository` write. The
/// cross-domain composite routes KnowledgeOS kinds here through the
/// `kKnowledgePack` proposal applier route.
///
/// Handled kinds:
///  - `capture_upgrade`        → Capture-sheet-equivalent promotion:
///                               routine rows are created and temp notes are
///                               tombstoned; other detected kinds update or
///                               create a candidate-tagged note.
///  - `knowledge_merge`        → `mergeNotes` / `mergeConcepts` /
///                               `mergePrinciples` / `mergeAssumptions` /
///                               `mergeDecisions` / `mergeExperiments`
///                               (§15.3 dedupe — assumption/principle/decision
///                               merges also re-point inbound references)
///  - `knowledge_routine`      → `upsertRoutine`
///  - `knowledge_concept_link` → `linkConcepts` (§14.2 — bidirectional edge)
///
/// Successful applies return `appliedAt` plus structured [undoData], so the
/// chat proposal card exposes the same 60s one-tap undo affordance FinanceOS
/// already has. Inbox kinds are intentionally not handled here — they flow
/// through the Review-tab triage side-table, not chat-apply (§5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../data/capture_kind.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';

export 'knowledge_proposal_kinds.dart' show kKnowledgeProposalAppliedKinds;

/// Drift table-name prefix for KnowledgeOS rows — used by the composite to
/// route [ProposalApplier.undo] (which carries the table, not the kind).
const String kKnowledgeTablePrefix = 'knowledge_';

class KnowledgeProposalApplier implements ProposalApplier {
  KnowledgeProposalApplier({
    required this.repo,
    required this.ownerUserId,
    required this.stamp,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final KnowledgeRepository repo;
  final String ownerUserId;

  /// Mints one fresh [SyncMeta] per touched row (own HLC). Production
  /// wiring delegates to [MutationStamper.stamp]; tests inject a fake.
  final Future<SyncMeta> Function() stamp;
  final DateTime Function() _now;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      return switch (plan.kind) {
        'capture_upgrade' => await _applyCaptureUpgrade(plan),
        'knowledge_merge' => await _applyMerge(plan),
        'knowledge_routine' => await _applyRoutine(plan),
        'knowledge_concept_link' => await _applyConceptLink(plan),
        _ => throw ProposalApplyException(
          'unknown knowledge proposal kind: ${plan.kind}',
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
    final undoData = state.undoData;
    if (undoData == null) {
      throw ProposalApplyException('KnowledgeOS undo data missing');
    }
    await _runUndoData(undoData);
  }

  Future<ProposalApplyState> _applyCaptureUpgrade(
    ReadyProposalPlan plan,
  ) async {
    final rawKind = plan.get('detected_kind');
    if (rawKind == null) {
      throw ProposalApplyException('capture_upgrade 缺少 detected_kind');
    }
    final detected = CaptureKind.parse(rawKind);
    if (detected == CaptureKind.note && rawKind != CaptureKind.note.wire) {
      throw ProposalApplyException(
        'capture_upgrade detected_kind 不支持: $rawKind',
      );
    }

    final noteId = plan.get('note_id');
    final existing = noteId == null
        ? null
        : await repo.findNote(ownerUserId: ownerUserId, id: noteId);
    if (noteId != null && existing == null) {
      throw ProposalApplyException('note $noteId 不存在');
    }

    if (detected == CaptureKind.routine) {
      final state = await _createRoutine(
        statement: _requireRoutineStatement(plan),
        intervalDays: _requireRoutineIntervalDays(plan),
        scope: plan.get('scope') ?? '*',
        nextDueAt: _parseOptionalUtc(plan.get('next_due_at')),
        summaryZh: plan.summaryZh,
      );
      if (existing != null) {
        final meta = await stamp();
        await repo.upsertNote(
          KnowledgeNote(
            id: existing.id,
            title: existing.title,
            bodyMd: existing.bodyMd,
            sourceUrl: existing.sourceUrl,
            tags: existing.tags,
            projectTag: existing.projectTag,
            createdAt: existing.createdAt,
            mergedIntoId: existing.mergedIntoId,
            sync: meta.copyWith(deletedAt: meta.updatedAt),
          ),
        );
      }
      return existing == null
          ? state
          : state.copyWith(
              undoData: _mergeUndoData(
                state.undoData,
                restore: [_snapshotNote(existing)],
              ),
            );
    }

    final meta = await stamp();
    final tags = <String>{...?existing?.tags};
    if (detected != CaptureKind.note) {
      tags.add('kind:${detected.wire}_candidate');
      final scope = plan.get('scope');
      if (scope != null) tags.add('scope:$scope');
    }

    final note = KnowledgeNote(
      id: existing?.id ?? kKnowledgeUuid.v4(),
      title: _captureTitle(plan, existing),
      bodyMd: _captureBody(plan, existing),
      sourceUrl: existing?.sourceUrl,
      tags: tags.toList(growable: false),
      projectTag: existing?.projectTag,
      createdAt: existing?.createdAt ?? meta.updatedAt,
      mergedIntoId: existing?.mergedIntoId,
      sync: meta,
    );
    await repo.upsertNote(note);

    final action = detected == CaptureKind.note ? '已更新 Note' : '已标记候选';
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: note.id,
      appliedTable: 'knowledge_notes',
      appliedAt: _now(),
      undoData: existing == null
          ? _undoData(delete: [_deleteRow('knowledge_notes', note.id)])
          : _undoData(restore: [_snapshotNote(existing)]),
      shortLabel:
          '$action：${_short(note.title.isEmpty ? note.bodyMd : note.title)}',
    );
  }

  Future<ProposalApplyState> _applyMerge(ReadyProposalPlan plan) async {
    final entityType = plan.get('entity_type');
    final primaryId = plan.get('primary_id');
    final dupRaw = plan.payload['duplicate_ids'];
    final duplicateIds = dupRaw is List
        ? dupRaw.whereType<String>().toList(growable: false)
        : const <String>[];
    if (primaryId == null || duplicateIds.isEmpty) {
      throw ProposalApplyException('merge 缺少 primary_id / duplicate_ids');
    }

    switch (entityType) {
      case 'note':
        final primary = await repo.findNote(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('note $primaryId 不存在');
        }
        final dups = <KnowledgeNote>[];
        final missing = <String>[];
        for (final id in duplicateIds) {
          final d = await repo.findNote(ownerUserId: ownerUserId, id: id);
          if (d == null) {
            missing.add(id);
          } else {
            dups.add(d);
          }
        }
        if (missing.isNotEmpty) {
          throw ProposalApplyException(
            '以下 note 不存在或不属于当前用户: ${missing.join(", ")}',
          );
        }
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 note');
        }
        final restore = <Map<String, Object?>>[
          _snapshotNote(primary),
          for (final d in dups) _snapshotNote(d),
        ];
        final survivor = await repo.mergeNotes(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
          mergedTitle: plan.get('merged_title'),
          mergedBody: plan.get('merged_body'),
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_notes',
          appliedAt: _now(),
          undoData: _undoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.title}」',
        );
      case 'concept':
        final primary = await repo.findConcept(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('concept $primaryId 不存在');
        }
        final dups = <KnowledgeConcept>[];
        final missing = <String>[];
        for (final id in duplicateIds) {
          final d = await repo.findConcept(ownerUserId: ownerUserId, id: id);
          if (d == null) {
            missing.add(id);
          } else {
            dups.add(d);
          }
        }
        if (missing.isNotEmpty) {
          throw ProposalApplyException(
            '以下 concept 不存在或不属于当前用户: ${missing.join(", ")}',
          );
        }
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 concept');
        }
        final restore = <Map<String, Object?>>[
          _snapshotConcept(primary),
          for (final d in dups) _snapshotConcept(d),
          ...await _conceptRepointSnapshots(primary, dups),
        ];
        final survivor = await repo.mergeConcepts(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
          mergedName: plan.get('merged_name'),
          mergedSummary: plan.get('merged_summary'),
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_concepts',
          appliedAt: _now(),
          undoData: _undoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.name}」',
        );
      case 'principle':
        final primary = await repo.findPrinciple(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('principle $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findPrinciple(ownerUserId: ownerUserId, id: id),
          entityType: 'principle',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 principle');
        }
        final restore = <Map<String, Object?>>[
          _snapshotPrinciple(primary),
          for (final d in dups) _snapshotPrinciple(d),
          ...await _principleRepointSnapshots(primary, dups),
        ];
        final survivor = await repo.mergePrinciples(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_principles',
          appliedAt: _now(),
          undoData: _undoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.statement}」',
        );
      case 'assumption':
        final primary = await repo.findAssumption(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('assumption $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findAssumption(ownerUserId: ownerUserId, id: id),
          entityType: 'assumption',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 assumption');
        }
        final restore = <Map<String, Object?>>[
          _snapshotAssumption(primary),
          for (final d in dups) _snapshotAssumption(d),
          ...await _assumptionRepointSnapshots(primary, dups),
        ];
        final survivor = await repo.mergeAssumptions(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_assumptions',
          appliedAt: _now(),
          undoData: _undoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.statement}」',
        );
      case 'decision':
        final primary = await repo.findDecision(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('decision $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findDecision(ownerUserId: ownerUserId, id: id),
          entityType: 'decision',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 decision');
        }
        final restore = <Map<String, Object?>>[
          _snapshotDecision(primary),
          for (final d in dups) _snapshotDecision(d),
          ...await _decisionRepointSnapshots(primary, dups),
        ];
        final survivor = await repo.mergeDecisions(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_decisions',
          appliedAt: _now(),
          undoData: _undoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.question}」',
        );
      case 'experiment':
        final primary = await repo.findExperiment(
          ownerUserId: ownerUserId,
          id: primaryId,
        );
        if (primary == null) {
          throw ProposalApplyException('experiment $primaryId 不存在');
        }
        final dups = await _hydrate(
          duplicateIds,
          (id) => repo.findExperiment(ownerUserId: ownerUserId, id: id),
          entityType: 'experiment',
        );
        if (dups.isEmpty) {
          throw ProposalApplyException('没有可合并的重复 experiment');
        }
        final restore = <Map<String, Object?>>[
          _snapshotExperiment(primary),
          for (final d in dups) _snapshotExperiment(d),
        ];
        final survivor = await repo.mergeExperiments(
          primary: primary,
          duplicates: dups,
          stamp: stamp,
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: survivor.id,
          appliedTable: 'knowledge_experiments',
          appliedAt: _now(),
          undoData: _undoData(restore: restore),
          shortLabel: '已合并 ${dups.length} 条到「${survivor.hypothesis}」',
        );
      default:
        throw ProposalApplyException(
          'merge entity_type 只支持 note / concept / principle / '
          'assumption / decision / experiment',
        );
    }
  }

  /// Hydrate ids into rows. Apply is all-or-nothing: missing ids usually
  /// mean the proposal is stale or points outside the active owner.
  Future<List<T>> _hydrate<T>(
    List<String> ids,
    Future<T?> Function(String) find, {
    required String entityType,
  }) async {
    final out = <T>[];
    final missing = <String>[];
    for (final id in ids) {
      final row = await find(id);
      if (row == null) {
        missing.add(id);
      } else {
        out.add(row);
      }
    }
    if (missing.isNotEmpty) {
      throw ProposalApplyException(
        '以下 $entityType 不存在或不属于当前用户: ${missing.join(", ")}',
      );
    }
    return out;
  }

  Future<ProposalApplyState> _applyConceptLink(ReadyProposalPlan plan) async {
    final fromId = plan.get('from_concept_id');
    final toId = plan.get('to_concept_id');
    if (fromId == null || toId == null || fromId == toId) {
      throw ProposalApplyException('concept_link 缺少 from/to 或两者相同');
    }
    final a = await repo.findConcept(ownerUserId: ownerUserId, id: fromId);
    final b = await repo.findConcept(ownerUserId: ownerUserId, id: toId);
    if (a == null || b == null) {
      throw ProposalApplyException('concept_link 引用的概念不存在');
    }
    final (updatedA, _) = await repo.linkConcepts(a: a, b: b, stamp: stamp);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: updatedA.id,
      appliedTable: 'knowledge_concepts',
      appliedAt: _now(),
      undoData: _undoData(restore: [_snapshotConcept(a), _snapshotConcept(b)]),
      shortLabel: '已关联「${a.name}」↔「${b.name}」',
    );
  }

  Future<ProposalApplyState> _applyRoutine(ReadyProposalPlan plan) async {
    return _createRoutine(
      statement: _requireRoutineStatement(plan),
      intervalDays: _requireRoutineIntervalDays(plan),
      scope: plan.get('scope') ?? '*',
      nextDueAt: _parseOptionalUtc(plan.get('next_due_at')),
      summaryZh: plan.summaryZh,
    );
  }

  Future<ProposalApplyState> _createRoutine({
    required String statement,
    required int intervalDays,
    required String scope,
    required DateTime? nextDueAt,
    required String summaryZh,
  }) async {
    final meta = await stamp();
    final routine = KnowledgeRoutine(
      id: kKnowledgeUuid.v4(),
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
      undoData: _undoData(
        delete: [_deleteRow('knowledge_routines', routine.id)],
      ),
      shortLabel: '已建立 Routine：${summaryZh.isEmpty ? statement : summaryZh}',
    );
  }

  Future<void> _runUndoData(Map<String, Object?> undoData) async {
    for (final row in _mapList(undoData['delete'])) {
      final table = row['table'] as String?;
      final id = row['id'] as String?;
      if (table == null || id == null) continue;
      final meta = await stamp();
      await repo.deleteEntry(
        kind: _kindForTable(table),
        id: id,
        sync: meta.copyWith(deletedAt: meta.updatedAt),
      );
    }

    for (final snapshot in _mapList(undoData['restore'])) {
      await _restoreSnapshot(snapshot);
    }
  }

  Future<void> _restoreSnapshot(Map<String, Object?> snapshot) async {
    final table = snapshot['table'] as String?;
    if (table == null) {
      throw ProposalApplyException('KnowledgeOS undo snapshot missing table');
    }
    final meta = _restoreSync(snapshot, await stamp());
    switch (table) {
      case 'knowledge_notes':
        await repo.upsertNote(_noteFromSnapshot(snapshot, meta));
      case 'knowledge_principles':
        await repo.upsertPrinciple(_principleFromSnapshot(snapshot, meta));
      case 'knowledge_assumptions':
        await repo.upsertAssumption(_assumptionFromSnapshot(snapshot, meta));
      case 'knowledge_decisions':
        await repo.upsertDecision(_decisionFromSnapshot(snapshot, meta));
      case 'knowledge_concepts':
        await repo.upsertConcept(_conceptFromSnapshot(snapshot, meta));
      case 'knowledge_experiments':
        await repo.upsertExperiment(_experimentFromSnapshot(snapshot, meta));
      case 'knowledge_routines':
        await repo.upsertRoutine(_routineFromSnapshot(snapshot, meta));
      default:
        throw ProposalApplyException('unknown knowledge undo table: $table');
    }
  }

  Future<List<Map<String, Object?>>> _conceptRepointSnapshots(
    KnowledgeConcept primary,
    List<KnowledgeConcept> duplicates,
  ) async {
    final dupIds = duplicates.map((d) => d.id).toSet();
    final concepts = await repo.listConcepts(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    return [
      for (final concept in concepts)
        if (concept.id != primary.id &&
            !dupIds.contains(concept.id) &&
            concept.relatedConceptIds.any(dupIds.contains))
          _snapshotConcept(concept),
    ];
  }

  Future<List<Map<String, Object?>>> _principleRepointSnapshots(
    KnowledgePrinciple primary,
    List<KnowledgePrinciple> duplicates,
  ) async {
    final dupIds = duplicates.map((d) => d.id).toSet();
    final decisions = await repo.listDecisions(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    return [
      for (final decision in decisions)
        if (decision.principleIds.any(dupIds.contains))
          _snapshotDecision(decision),
    ];
  }

  Future<List<Map<String, Object?>>> _assumptionRepointSnapshots(
    KnowledgeAssumption primary,
    List<KnowledgeAssumption> duplicates,
  ) async {
    final dupIds = duplicates.map((d) => d.id).toSet();
    final decisions = await repo.listDecisions(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    final experiments = await repo.listExperiments(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    return [
      for (final decision in decisions)
        if (decision.assumptionIds.any(dupIds.contains))
          _snapshotDecision(decision),
      for (final experiment in experiments)
        if (dupIds.contains(experiment.targetAssumptionId))
          _snapshotExperiment(experiment),
    ];
  }

  Future<List<Map<String, Object?>>> _decisionRepointSnapshots(
    KnowledgeDecision primary,
    List<KnowledgeDecision> duplicates,
  ) async {
    final dupIds = duplicates.map((d) => d.id).toSet();
    final decisions = await repo.listDecisions(
      ownerUserId: primary.sync.ownerUserId,
      limit: _allRows,
    );
    return [
      for (final decision in decisions)
        if (decision.id != primary.id &&
            !dupIds.contains(decision.id) &&
            dupIds.contains(decision.supersededByDecisionId))
          _snapshotDecision(decision),
    ];
  }
}

const int _allRows = 100000;

Map<String, Object?> _undoData({
  List<Map<String, Object?>> restore = const [],
  List<Map<String, Object?>> delete = const [],
}) => <String, Object?>{
  if (restore.isNotEmpty) 'restore': restore,
  if (delete.isNotEmpty) 'delete': delete,
};

Map<String, Object?> _mergeUndoData(
  Map<String, Object?>? base, {
  List<Map<String, Object?>> restore = const [],
  List<Map<String, Object?>> delete = const [],
}) {
  return _undoData(
    restore: [..._mapList(base?['restore']), ...restore],
    delete: [..._mapList(base?['delete']), ...delete],
  );
}

Map<String, Object?> _deleteRow(String table, String id) => <String, Object?>{
  'table': table,
  'id': id,
};

Iterable<Map<String, Object?>> _mapList(Object? raw) sync* {
  if (raw is! List) return;
  for (final item in raw) {
    if (item is Map) {
      yield item.map((key, value) => MapEntry(key.toString(), value));
    }
  }
}

KnowledgeEntryKind _kindForTable(String table) => switch (table) {
  'knowledge_notes' => KnowledgeEntryKind.note,
  'knowledge_principles' => KnowledgeEntryKind.principle,
  'knowledge_assumptions' => KnowledgeEntryKind.assumption,
  'knowledge_decisions' => KnowledgeEntryKind.decision,
  'knowledge_concepts' => KnowledgeEntryKind.concept,
  'knowledge_experiments' => KnowledgeEntryKind.experiment,
  'knowledge_routines' => KnowledgeEntryKind.routine,
  _ => throw ProposalApplyException('unknown knowledge undo table: $table'),
};

Map<String, Object?> _snapshotBase(String table, String id, SyncMeta sync) =>
    <String, Object?>{
      'table': table,
      'id': id,
      if (sync.deletedAt != null)
        'deleted_at': sync.deletedAt!.toUtc().toIso8601String(),
    };

Map<String, Object?> _snapshotNote(KnowledgeNote note) => <String, Object?>{
  ..._snapshotBase('knowledge_notes', note.id, note.sync),
  'title': note.title,
  'body_md': note.bodyMd,
  'source_url': note.sourceUrl,
  'tags': note.tags,
  'project_tag': note.projectTag,
  'created_at': note.createdAt.toUtc().toIso8601String(),
  'merged_into_id': note.mergedIntoId,
};

Map<String, Object?> _snapshotPrinciple(KnowledgePrinciple p) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_principles', p.id, p.sync),
      'statement': p.statement,
      'rationale_md': p.rationaleMd,
      'scope': p.scope,
      'status': p.status.wire,
      'declared_at': p.declaredAt.toUtc().toIso8601String(),
      'merged_into_id': p.mergedIntoId,
    };

Map<String, Object?> _snapshotAssumption(KnowledgeAssumption a) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_assumptions', a.id, a.sync),
      'statement': a.statement,
      'confidence': a.confidence,
      'scope': a.scope,
      'evidence_ids': a.evidenceIds,
      'status': a.status.wire,
      'declared_at': a.declaredAt.toUtc().toIso8601String(),
      'last_verified_at': a.lastVerifiedAt?.toUtc().toIso8601String(),
      'merged_into_id': a.mergedIntoId,
    };

Map<String, Object?> _snapshotDecision(KnowledgeDecision d) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_decisions', d.id, d.sync),
      'question': d.question,
      'options': [for (final option in d.options) option.toJson()],
      'selected_label': d.selectedLabel,
      'rationale_md': d.rationaleMd,
      'principle_ids': d.principleIds,
      'assumption_ids': d.assumptionIds,
      'expected_outcome': d.expectedOutcome,
      'review_date': d.reviewDate?.toUtc().toIso8601String(),
      'actual_outcome_md': d.actualOutcomeMd,
      'status': d.status.wire,
      'superseded_by_decision_id': d.supersededByDecisionId,
      'context_snapshot': d.contextSnapshot,
      'decided_at': d.decidedAt.toUtc().toIso8601String(),
      'merged_into_id': d.mergedIntoId,
    };

Map<String, Object?> _snapshotConcept(KnowledgeConcept c) => <String, Object?>{
  ..._snapshotBase('knowledge_concepts', c.id, c.sync),
  'name': c.name,
  'aliases': c.aliases,
  'summary_md': c.summaryMd,
  'related_concept_ids': c.relatedConceptIds,
  'created_at': c.createdAt.toUtc().toIso8601String(),
  'merged_into_id': c.mergedIntoId,
};

Map<String, Object?> _snapshotExperiment(KnowledgeExperiment e) =>
    <String, Object?>{
      ..._snapshotBase('knowledge_experiments', e.id, e.sync),
      'hypothesis': e.hypothesis,
      'method_md': e.methodMd,
      'metrics': e.metrics,
      'status': e.status.wire,
      'result_md': e.resultMd,
      'conclusion_md': e.conclusionMd,
      'target_assumption_id': e.targetAssumptionId,
      'started_at': e.startedAt.toUtc().toIso8601String(),
      'ended_at': e.endedAt?.toUtc().toIso8601String(),
      'merged_into_id': e.mergedIntoId,
    };

SyncMeta _restoreSync(Map<String, Object?> snapshot, SyncMeta meta) {
  final deletedAt = _dateOrNull(snapshot['deleted_at']);
  return meta.copyWith(deletedAt: deletedAt == null ? null : meta.updatedAt);
}

KnowledgeNote _noteFromSnapshot(Map<String, Object?> s, SyncMeta sync) =>
    KnowledgeNote(
      id: _string(s, 'id'),
      title: _string(s, 'title'),
      bodyMd: _string(s, 'body_md'),
      sourceUrl: s['source_url'] as String?,
      tags: _stringList(s['tags']),
      projectTag: s['project_tag'] as String?,
      createdAt: _date(s['created_at']),
      mergedIntoId: s['merged_into_id'] as String?,
      sync: sync,
    );

KnowledgePrinciple _principleFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgePrinciple(
  id: _string(s, 'id'),
  statement: _string(s, 'statement'),
  rationaleMd: _string(s, 'rationale_md'),
  scope: _string(s, 'scope'),
  status: PrincipleStatus.parse(_string(s, 'status')),
  declaredAt: _date(s['declared_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeAssumption _assumptionFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeAssumption(
  id: _string(s, 'id'),
  statement: _string(s, 'statement'),
  confidence: (s['confidence'] as num?)?.toDouble() ?? 0,
  scope: _string(s, 'scope'),
  evidenceIds: _stringList(s['evidence_ids']),
  status: AssumptionStatus.parse(_string(s, 'status')),
  declaredAt: _date(s['declared_at']),
  lastVerifiedAt: _dateOrNull(s['last_verified_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeDecision _decisionFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeDecision(
  id: _string(s, 'id'),
  question: _string(s, 'question'),
  options: [
    for (final raw in _mapList(s['options'])) DecisionOption.fromJson(raw),
  ],
  selectedLabel: _string(s, 'selected_label'),
  rationaleMd: _string(s, 'rationale_md'),
  principleIds: _stringList(s['principle_ids']),
  assumptionIds: _stringList(s['assumption_ids']),
  expectedOutcome: s['expected_outcome'] as String?,
  reviewDate: _dateOrNull(s['review_date']),
  actualOutcomeMd: s['actual_outcome_md'] as String?,
  status: DecisionStatus.parse(_string(s, 'status')),
  supersededByDecisionId: s['superseded_by_decision_id'] as String?,
  contextSnapshot: _mapOrNull(s['context_snapshot']),
  decidedAt: _date(s['decided_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeConcept _conceptFromSnapshot(Map<String, Object?> s, SyncMeta sync) =>
    KnowledgeConcept(
      id: _string(s, 'id'),
      name: _string(s, 'name'),
      aliases: _stringList(s['aliases']),
      summaryMd: _string(s, 'summary_md'),
      relatedConceptIds: _stringList(s['related_concept_ids']),
      createdAt: _date(s['created_at']),
      mergedIntoId: s['merged_into_id'] as String?,
      sync: sync,
    );

KnowledgeExperiment _experimentFromSnapshot(
  Map<String, Object?> s,
  SyncMeta sync,
) => KnowledgeExperiment(
  id: _string(s, 'id'),
  hypothesis: _string(s, 'hypothesis'),
  methodMd: _string(s, 'method_md'),
  metrics: _stringList(s['metrics']),
  status: ExperimentStatus.parse(_string(s, 'status')),
  resultMd: s['result_md'] as String?,
  conclusionMd: s['conclusion_md'] as String?,
  targetAssumptionId: s['target_assumption_id'] as String?,
  startedAt: _date(s['started_at']),
  endedAt: _dateOrNull(s['ended_at']),
  mergedIntoId: s['merged_into_id'] as String?,
  sync: sync,
);

KnowledgeRoutine _routineFromSnapshot(Map<String, Object?> s, SyncMeta sync) =>
    KnowledgeRoutine(
      id: _string(s, 'id'),
      statement: _string(s, 'statement'),
      intervalDays: (s['interval_days'] as num?)?.toInt() ?? 1,
      lastDoneAt: _dateOrNull(s['last_done_at']),
      nextDueAt: _date(s['next_due_at']),
      scope: _string(s, 'scope'),
      status: RoutineStatus.parse(_string(s, 'status')),
      createdAt: _date(s['created_at']),
      sync: sync,
    );

String _string(Map<String, Object?> map, String key) =>
    (map[key] as String?) ?? '';

List<String> _stringList(Object? raw) =>
    raw is List ? raw.whereType<String>().toList(growable: false) : const [];

Map<String, Object?>? _mapOrNull(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : null;

DateTime _date(Object? raw) => DateTime.parse(raw as String).toUtc();

DateTime? _dateOrNull(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

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

String _captureTitle(ReadyProposalPlan plan, KnowledgeNote? existing) {
  final polished = plan.get('polished_title');
  if (polished != null) return polished;
  if (existing != null && existing.title.trim().isNotEmpty) {
    return existing.title.trim();
  }
  final statement = plan.get('statement');
  if (statement != null) {
    return _short(statement, max: kKnowledgeHeadlineExcerptMaxChars);
  }
  final source = plan.get('source_text');
  if (source != null) {
    return _short(
      source.split('\n').first.trim(),
      max: kKnowledgeHeadlineExcerptMaxChars,
    );
  }
  return '';
}

String _captureBody(ReadyProposalPlan plan, KnowledgeNote? existing) {
  final polished = plan.get('polished_body');
  if (polished != null) return polished;
  if (existing != null && existing.bodyMd.trim().isNotEmpty) {
    return existing.bodyMd;
  }
  return plan.get('source_text') ?? plan.get('statement') ?? '';
}

String _short(String value, {int max = kKnowledgeInlineExcerptMaxChars}) {
  final trimmed = value.trim();
  return knowledgeExcerpt(trimmed, max: max);
}

/// KnowledgeOS applier wiring. Resolves the repo + a per-row [SyncMeta]
/// factory from the stamper. `kKnowledgePack` uses this provider to build
/// its cross-domain proposal route.
final knowledgeProposalApplierProvider =
    FutureProvider<KnowledgeProposalApplier>((ref) async {
      final repo = await ref.watch(knowledgeRepositoryProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      final stamper = await ref.watch(mutationStamperProvider.future);
      return KnowledgeProposalApplier(
        repo: repo,
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
