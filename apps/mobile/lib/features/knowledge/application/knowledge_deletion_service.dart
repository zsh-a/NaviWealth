import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

class KnowledgeDeleteImpact {
  const KnowledgeDeleteImpact({
    required this.relationCount,
    required this.referenceCount,
    required this.attachmentCount,
  });

  final int relationCount;
  final int referenceCount;
  final int attachmentCount;

  bool get hasDependencies =>
      relationCount > 0 || referenceCount > 0 || attachmentCount > 0;
}

class KnowledgeDeleteChange {
  const KnowledgeDeleteChange(this.undo);

  final Future<bool> Function() undo;
}

final knowledgeDeletionServiceProvider =
    FutureProvider<KnowledgeDeletionService>((ref) async {
      return KnowledgeDeletionService(
        repository: await ref.watch(knowledgeRepositoryProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

/// Coordinates object deletion with relation cleanup and guarded restore.
class KnowledgeDeletionService {
  KnowledgeDeletionService({
    required KnowledgeRepository repository,
    required MutationStamper stamper,
  }) : _repository = repository,
       _stamper = stamper;

  final KnowledgeRepository _repository;
  final MutationStamper _stamper;

  Future<KnowledgeDeleteImpact> analyze({
    required String ownerUserId,
    required KnowledgeEntryKind kind,
    required String id,
  }) async {
    final relations = await _repository.listRelationsForObject(
      ownerUserId: ownerUserId,
      kind: kind.name,
      id: id,
    );
    var references = 0;

    final decisions = await _repository.listDecisions(ownerUserId: ownerUserId);
    for (final decision in decisions) {
      if (kind == KnowledgeEntryKind.principle &&
          decision.principleIds.contains(id)) {
        references++;
      }
      if (kind == KnowledgeEntryKind.assumption &&
          decision.assumptionIds.contains(id)) {
        references++;
      }
    }

    final assumptions = await _repository.listAssumptions(
      ownerUserId: ownerUserId,
    );
    if (kind == KnowledgeEntryKind.note) {
      references += assumptions
          .where((item) => item.evidenceIds.contains(id))
          .length;
    }

    final experiments = await _repository.listExperiments(
      ownerUserId: ownerUserId,
    );
    if (kind == KnowledgeEntryKind.assumption) {
      references += experiments
          .where((item) => item.targetAssumptionId == id)
          .length;
    }

    final concepts = await _repository.listConcepts(ownerUserId: ownerUserId);
    if (kind == KnowledgeEntryKind.concept) {
      references += concepts
          .where((item) => item.id != id && item.relatedConceptIds.contains(id))
          .length;
    }

    final notes = await _repository.listNotes(ownerUserId: ownerUserId);
    references += notes
        .where(
          (item) => item.promotedToKind == kind.name && item.promotedToId == id,
        )
        .length;
    final note = kind == KnowledgeEntryKind.note
        ? notes.where((item) => item.id == id).firstOrNull
        : null;

    return KnowledgeDeleteImpact(
      relationCount: relations.length,
      referenceCount: references,
      attachmentCount: note == null ? 0 : _attachmentCount(note.bodyMd),
    );
  }

  Future<KnowledgeDeleteChange?> delete({
    required String ownerUserId,
    required KnowledgeEntryKind kind,
    required String id,
  }) async {
    final entry = await _findEntry(
      ownerUserId: ownerUserId,
      kind: kind,
      id: id,
    );
    if (entry == null || _syncOf(entry).deletedAt != null) return null;
    final relations = await _repository.listRelationsForObject(
      ownerUserId: ownerUserId,
      kind: kind.name,
      id: id,
    );
    final freshDeleteSync = await _freshSync();
    final deleteSync = freshDeleteSync.copyWith(
      deletedAt: freshDeleteSync.updatedAt,
    );
    await _repository.deleteEntry(kind: kind, id: id, sync: deleteSync);

    return KnowledgeDeleteChange(() async {
      final current = await _findEntry(
        ownerUserId: ownerUserId,
        kind: kind,
        id: id,
      );
      if (current == null ||
          _syncOf(current).deletedAt == null ||
          _syncOf(current).hlc != deleteSync.hlc) {
        return false;
      }

      final restoreSync = await _freshSync();
      await _upsertEntry(_entryWithSync(entry, restoreSync));
      for (final relation in relations) {
        final latest = await _repository.findRelation(
          ownerUserId: ownerUserId,
          id: relation.id,
        );
        if (latest == null ||
            latest.sync.deletedAt == null ||
            latest.sync.hlc != deleteSync.hlc) {
          continue;
        }
        await _repository.upsertRelation(
          KnowledgeRelation(
            id: relation.id,
            fromKind: relation.fromKind,
            fromId: relation.fromId,
            relation: relation.relation,
            toKind: relation.toKind,
            toId: relation.toId,
            createdAt: relation.createdAt,
            sync: restoreSync,
          ),
        );
      }
      return true;
    });
  }

  Future<SyncMeta> _freshSync() async {
    final stamp = await _stamper.stamp();
    return SyncMeta(
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
  }

  Future<Object?> _findEntry({
    required String ownerUserId,
    required KnowledgeEntryKind kind,
    required String id,
  }) => switch (kind) {
    KnowledgeEntryKind.note => _repository.findNote(
      ownerUserId: ownerUserId,
      id: id,
    ),
    KnowledgeEntryKind.principle => _repository.findPrinciple(
      ownerUserId: ownerUserId,
      id: id,
    ),
    KnowledgeEntryKind.assumption => _repository.findAssumption(
      ownerUserId: ownerUserId,
      id: id,
    ),
    KnowledgeEntryKind.decision => _repository.findDecision(
      ownerUserId: ownerUserId,
      id: id,
    ),
    KnowledgeEntryKind.concept => _repository.findConcept(
      ownerUserId: ownerUserId,
      id: id,
    ),
    KnowledgeEntryKind.experiment => _repository.findExperiment(
      ownerUserId: ownerUserId,
      id: id,
    ),
    KnowledgeEntryKind.routine => _repository.findRoutine(
      ownerUserId: ownerUserId,
      id: id,
    ),
  };

  Future<void> _upsertEntry(Object entry) => switch (entry) {
    KnowledgeNote value => _repository.upsertNote(value),
    KnowledgePrinciple value => _repository.upsertPrinciple(value),
    KnowledgeAssumption value => _repository.upsertAssumption(value),
    KnowledgeDecision value => _repository.upsertDecision(value),
    KnowledgeConcept value => _repository.upsertConcept(value),
    KnowledgeExperiment value => _repository.upsertExperiment(value),
    KnowledgeRoutine value => _repository.upsertRoutine(value),
    _ => Future<void>.error(ArgumentError.value(entry, 'entry')),
  };
}

SyncMeta _syncOf(Object entry) => switch (entry) {
  KnowledgeNote value => value.sync,
  KnowledgePrinciple value => value.sync,
  KnowledgeAssumption value => value.sync,
  KnowledgeDecision value => value.sync,
  KnowledgeConcept value => value.sync,
  KnowledgeExperiment value => value.sync,
  KnowledgeRoutine value => value.sync,
  _ => throw ArgumentError.value(entry, 'entry'),
};

Object _entryWithSync(Object entry, SyncMeta sync) => switch (entry) {
  KnowledgeNote value => KnowledgeNote(
    id: value.id,
    title: value.title,
    bodyMd: value.bodyMd,
    sourceUrl: value.sourceUrl,
    tags: value.tags,
    projectTag: value.projectTag,
    createdAt: value.createdAt,
    promotedToKind: value.promotedToKind,
    promotedToId: value.promotedToId,
    promotedAt: value.promotedAt,
    mergedIntoId: value.mergedIntoId,
    sync: sync,
  ),
  KnowledgePrinciple value => KnowledgePrinciple(
    id: value.id,
    statement: value.statement,
    rationaleMd: value.rationaleMd,
    scope: value.scope,
    status: value.status,
    declaredAt: value.declaredAt,
    mergedIntoId: value.mergedIntoId,
    sync: sync,
  ),
  KnowledgeAssumption value => KnowledgeAssumption(
    id: value.id,
    statement: value.statement,
    confidence: value.confidence,
    scope: value.scope,
    evidenceIds: value.evidenceIds,
    status: value.status,
    declaredAt: value.declaredAt,
    lastVerifiedAt: value.lastVerifiedAt,
    mergedIntoId: value.mergedIntoId,
    sync: sync,
  ),
  KnowledgeDecision value => KnowledgeDecision(
    id: value.id,
    question: value.question,
    options: value.options,
    selectedLabel: value.selectedLabel,
    rationaleMd: value.rationaleMd,
    principleIds: value.principleIds,
    assumptionIds: value.assumptionIds,
    expectedOutcome: value.expectedOutcome,
    reviewDate: value.reviewDate,
    actualOutcomeMd: value.actualOutcomeMd,
    status: value.status,
    supersededByDecisionId: value.supersededByDecisionId,
    contextSnapshot: value.contextSnapshot,
    decidedAt: value.decidedAt,
    mergedIntoId: value.mergedIntoId,
    sync: sync,
  ),
  KnowledgeConcept value => KnowledgeConcept(
    id: value.id,
    name: value.name,
    aliases: value.aliases,
    summaryMd: value.summaryMd,
    relatedConceptIds: value.relatedConceptIds,
    createdAt: value.createdAt,
    mergedIntoId: value.mergedIntoId,
    sync: sync,
  ),
  KnowledgeExperiment value => KnowledgeExperiment(
    id: value.id,
    hypothesis: value.hypothesis,
    methodMd: value.methodMd,
    metrics: value.metrics,
    status: value.status,
    resultMd: value.resultMd,
    conclusionMd: value.conclusionMd,
    targetAssumptionId: value.targetAssumptionId,
    startedAt: value.startedAt,
    endedAt: value.endedAt,
    mergedIntoId: value.mergedIntoId,
    sync: sync,
  ),
  KnowledgeRoutine value => KnowledgeRoutine(
    id: value.id,
    statement: value.statement,
    intervalDays: value.intervalDays,
    nextDueAt: value.nextDueAt,
    lastDoneAt: value.lastDoneAt,
    scope: value.scope,
    status: value.status,
    createdAt: value.createdAt,
    sync: sync,
  ),
  _ => throw ArgumentError.value(entry, 'entry'),
};

int _attachmentCount(String markdown) {
  final ids = <String>{};
  final patterns = <RegExp>[
    RegExp(r'attachment://([^\s)]+)'),
    RegExp(r'/attachments/([^\s)]+)'),
  ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(markdown)) {
      final id = match.group(1);
      if (id != null && id.isNotEmpty) ids.add(id);
    }
  }
  return ids.length;
}
