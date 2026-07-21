/// KnowledgeOS read / write API (`docs/domains/knowledgeos-domain.md` §3 + §9).
///
/// Thin Drift wrapper over the typed `knowledge_*` tables. Mirrors
/// `HealthMetricRepository`: the caller stamps sync metadata via the
/// cross-domain `mutationStamperProvider` and passes the stamped
/// `SyncMeta` in on every write. The repository owns the
/// transaction + outbox enqueue.
library;

import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/knowledge_models.dart';
import 'knowledge_row_mappers.dart';

part 'knowledge_repository_assumptions.dart';
part 'knowledge_repository_concepts.dart';
part 'knowledge_repository_decisions.dart';
part 'knowledge_repository_experiments.dart';
part 'knowledge_repository_merge.dart';
part 'knowledge_repository_merge_assumptions.dart';
part 'knowledge_repository_merge_concepts.dart';
part 'knowledge_repository_merge_decisions.dart';
part 'knowledge_repository_merge_experiments.dart';
part 'knowledge_repository_merge_helpers.dart';
part 'knowledge_repository_merge_notes.dart';
part 'knowledge_repository_merge_principles.dart';
part 'knowledge_repository_notes.dart';
part 'knowledge_repository_principles.dart';
part 'knowledge_repository_promotions.dart';
part 'knowledge_repository_routines.dart';

const String _knowledgeNotesTable = 'knowledge_notes';
const String _knowledgePrinciplesTable = 'knowledge_principles';
const String _knowledgeAssumptionsTable = 'knowledge_assumptions';
const String _knowledgeDecisionsTable = 'knowledge_decisions';
const String _knowledgeConceptsTable = 'knowledge_concepts';
const String _knowledgeExperimentsTable = 'knowledge_experiments';
const String _knowledgeRoutinesTable = 'knowledge_routines';

enum KnowledgeEntryKind {
  note('knowledge_notes'),
  principle('knowledge_principles'),
  assumption('knowledge_assumptions'),
  decision('knowledge_decisions'),
  concept('knowledge_concepts'),
  experiment('knowledge_experiments'),
  routine('knowledge_routines');

  const KnowledgeEntryKind(this.tableName);

  final String tableName;
}

String experimentConclusionNoteId(String experimentId) =>
    'experiment_conclusion:$experimentId';

class KnowledgeExperimentClosure {
  const KnowledgeExperimentClosure({
    required this.experiment,
    this.evidenceNote,
    this.targetAssumption,
  });

  final KnowledgeExperiment experiment;
  final KnowledgeNote? evidenceNote;
  final KnowledgeAssumption? targetAssumption;
}

class KnowledgeRepository
    with
        KnowledgeNotesRepositoryMixin,
        KnowledgePrinciplesRepositoryMixin,
        KnowledgeAssumptionsRepositoryMixin,
        KnowledgeDecisionsRepositoryMixin,
        KnowledgeConceptsRepositoryMixin,
        KnowledgeExperimentsRepositoryMixin,
        KnowledgeRoutinesRepositoryMixin,
        KnowledgePromotionsRepositoryMixin,
        KnowledgeRepositoryMerge {
  KnowledgeRepository({required AppDatabase db, required OutboxStore outbox})
    : _db = db,
      _outbox = outbox;

  @override
  final AppDatabase _db;
  @override
  final OutboxStore _outbox;

  /// Shared write path for typed KnowledgeOS tables: open a
  /// transaction, upsert via `insertOrReplace`, then enqueue the
  /// dirty-pointer outbox entry for sync. The previous version of
  /// this file repeated that 4-line dance in every `upsertX` —
  /// mechanical and identical across types, so collapsed here.
  @override
  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  }) async {
    await _db.transaction(() async {
      await _db.into(table).insert(companion, mode: InsertMode.insertOrReplace);
      await _outbox.enqueue(table: tableName, rowId: rowId);
    });
  }

  /// Soft-delete one KnowledgeOS row using the shared sync columns.
  ///
  /// This is intentionally type-agnostic: every `knowledge_*` table carries
  /// the same `SyncableTable` metadata, so Library UI delete can stay one
  /// path while still writing a tombstone peers can sync.
  Future<void> deleteEntry({
    required KnowledgeEntryKind kind,
    required String id,
    required SyncMeta sync,
  }) async {
    final deletedAt = sync.deletedAt ?? sync.updatedAt;
    await _db.transaction(() async {
      final changed = await _db.customUpdate(
        '''
UPDATE ${kind.tableName}
SET updated_at = ?, updated_by_device = ?, hlc = ?, deleted_at = ?
WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL
''',
        variables: [
          Variable<DateTime>(sync.updatedAt),
          Variable<String>(sync.updatedByDevice),
          Variable<String>(sync.hlc.toString()),
          Variable<DateTime>(deletedAt),
          Variable<String>(id),
          Variable<String>(sync.ownerUserId),
        ],
        updates: {_tableFor(kind)},
      );
      if (changed > 0) {
        await _outbox.enqueue(table: kind.tableName, rowId: id);
      }
    });
  }

  TableInfo<Table, Object?> _tableFor(KnowledgeEntryKind kind) =>
      switch (kind) {
        KnowledgeEntryKind.note => _db.knowledgeNotes,
        KnowledgeEntryKind.principle => _db.knowledgePrinciples,
        KnowledgeEntryKind.assumption => _db.knowledgeAssumptions,
        KnowledgeEntryKind.decision => _db.knowledgeDecisions,
        KnowledgeEntryKind.concept => _db.knowledgeConcepts,
        KnowledgeEntryKind.experiment => _db.knowledgeExperiments,
        KnowledgeEntryKind.routine => _db.knowledgeRoutines,
      };
}
