/// KnowledgeOS Drift tables (`docs/domains/knowledgeos-domain.md` §3 + §9).
///
/// Six tables — Notes / Principles / Assumptions / Decisions / Concepts /
/// Experiments. Memory is *not* a separate table here: per §3 it reuses
/// Memory Layer `kind='semantic'` records directly.
///
/// All tables wear [SyncableTable] and carry the `know:` row family
/// prefix on the wire (see `core/sync/domain_prefix.dart` and
/// `docs/architecture/lifeos-shell.md` §8). The local table names stay unprefixed —
/// the prefix is applied at the sync boundary only.
library;

import 'package:drift/drift.dart';

import 'tables.dart' show SyncableTable;

/// Free-form knowledge note. Markdown body — no rich-text / block editor
/// per the §8 反目标 ("KnowledgeOS 不是 AI Notion").
@DataClassName('KnowledgeNoteRow')
class KnowledgeNotes extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get bodyMd => text()();
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get projectTag => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  /// Dedupe pointer (`docs/domains/knowledgeos-domain.md` §15.3). When this note
  /// is merged into another note via `propose_merge`, it is soft-deleted
  /// (`deletedAt` set) AND stamped with the surviving note's id here, so
  /// a future un-merge / audit can find where the content went. NULL for
  /// every live note.
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Long-term worldview primitive ("默认 edge-first").
/// `status: active | paused | retired`. Not falsifiable — only retire-able.
@DataClassName('KnowledgePrincipleRow')
class KnowledgePrinciples extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get statement => text()();
  TextColumn get rationaleMd => text().withDefault(const Constant(''))();
  TextColumn get scope => text().withDefault(const Constant('*'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get declaredAt => dateTime()();

  /// Dedupe pointer — see [KnowledgeNotes.mergedIntoId]. A principle merged
  /// into another is soft-deleted and stamped with the survivor's id; any
  /// Decision referencing it is re-pointed to the survivor (§15.3 P1).
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Falsifiable assumption with confidence & evidence trail.
/// `status: active | weakened | falsified | retired`.
@DataClassName('KnowledgeAssumptionRow')
class KnowledgeAssumptions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get statement => text()();
  RealColumn get confidence => real().withDefault(const Constant(0.7))();
  TextColumn get scope => text().withDefault(const Constant('*'))();
  TextColumn get evidenceIdsJson => text().withDefault(const Constant('[]'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get lastVerifiedAt => dateTime().nullable()();
  DateTimeColumn get declaredAt => dateTime()();

  /// Dedupe pointer — see [KnowledgeNotes.mergedIntoId]. An assumption merged
  /// into another is soft-deleted and stamped with the survivor's id; any
  /// Decision (`assumptionIds`) or Experiment (`targetAssumptionId`)
  /// referencing it is re-pointed to the survivor (§15.3 P1).
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Decision with options, rationale, expected outcome, review date,
/// principle + assumption references, optional cross-domain snapshot,
/// and 7-state lifecycle.
///
/// `status: draft | active | paused | expired | verified | falsified | superseded`.
@DataClassName('KnowledgeDecisionRow')
class KnowledgeDecisions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get question => text()();
  TextColumn get optionsJson => text().withDefault(const Constant('[]'))();
  TextColumn get selectedLabel => text().withDefault(const Constant(''))();
  TextColumn get rationaleMd => text().withDefault(const Constant(''))();
  TextColumn get principleIdsJson => text().withDefault(const Constant('[]'))();
  TextColumn get assumptionIdsJson => text().withDefault(const Constant('[]'))();
  TextColumn get expectedOutcome => text().nullable()();
  DateTimeColumn get reviewDate => dateTime().nullable()();
  TextColumn get actualOutcomeMd => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get supersededByDecisionId => text().nullable()();
  TextColumn get contextSnapshotJson => text().nullable()();
  DateTimeColumn get decidedAt => dateTime()();

  /// Dedupe pointer — see [KnowledgeNotes.mergedIntoId]. A decision merged
  /// into another is soft-deleted and stamped with the survivor's id; any
  /// other decision whose `supersededByDecisionId` pointed at it is
  /// re-pointed to the survivor (§15.3 P1). Distinct from `superseded`
  /// status — merge is "these were the same decision", supersede is
  /// "a later decision replaced this one".
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Lightweight concept node — used to anchor `[[concept]]` soft links
/// and AI-proposed cross-references.
@DataClassName('KnowledgeConceptRow')
class KnowledgeConcepts extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get aliasesJson => text().withDefault(const Constant('[]'))();
  TextColumn get summaryMd => text().withDefault(const Constant(''))();
  TextColumn get relatedConceptIdsJson =>
      text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();

  /// Dedupe pointer — see [KnowledgeNotes.mergedIntoId]. When this concept
  /// is merged into another, it is soft-deleted and stamped with the
  /// survivor's id; the survivor unions aliases + relatedConceptIds.
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Experiment — typically pointed at an assumption it tests.
/// `status: planned | running | done | abandoned`.
@DataClassName('KnowledgeExperimentRow')
class KnowledgeExperiments extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get hypothesis => text()();
  TextColumn get methodMd => text().withDefault(const Constant(''))();
  TextColumn get metricsJson => text().withDefault(const Constant('[]'))();
  TextColumn get status => text().withDefault(const Constant('planned'))();
  TextColumn get resultMd => text().nullable()();
  TextColumn get conclusionMd => text().nullable()();
  TextColumn get targetAssumptionId => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Dedupe pointer — see [KnowledgeNotes.mergedIntoId]. Experiments carry no
  /// inbound id references, so a merge only unions metrics onto the survivor
  /// and tombstones the duplicate (no re-pointing needed).
  TextColumn get mergedIntoId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Recurring user-defined reminder ("港卡每 6 个月做一次活跃交易"). A first-class
/// type alongside Decision / Assumption / ... because the cadence + last-done
/// state needs a stable row to advance against — a plain Note can carry the
/// text but has no place to record "lastDoneAt → nextDueAt". RoutineDueAgent
/// scans `next_due_at <= now + 7d` daily and emits a memory + local
/// notification on the `lifeos.knowledge.review` channel.
/// `status: active | paused | archived`.
@DataClassName('KnowledgeRoutineRow')
class KnowledgeRoutines extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get statement => text()();
  IntColumn get intervalDays => integer()();
  DateTimeColumn get lastDoneAt => dateTime().nullable()();
  DateTimeColumn get nextDueAt => dateTime()();
  TextColumn get scope => text().withDefault(const Constant('*'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Indexes & DDL companions for the KnowledgeOS tables. Mirrors the
/// HealthOS pattern in `app_database.dart`.
const List<String> knowledgeIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_knowledge_notes_owner_hlc '
      'ON knowledge_notes(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_notes_owner_created '
      'ON knowledge_notes(owner_user_id, created_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_principles_owner_hlc '
      'ON knowledge_principles(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_principles_status '
      'ON knowledge_principles(owner_user_id, status) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_assumptions_owner_hlc '
      'ON knowledge_assumptions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_assumptions_status '
      'ON knowledge_assumptions(owner_user_id, status) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_decisions_owner_hlc '
      'ON knowledge_decisions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_decisions_status_review '
      'ON knowledge_decisions(owner_user_id, status, review_date) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_concepts_owner_hlc '
      'ON knowledge_concepts(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_concepts_name '
      'ON knowledge_concepts(owner_user_id, name) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_experiments_owner_hlc '
      'ON knowledge_experiments(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_experiments_status '
      'ON knowledge_experiments(owner_user_id, status) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_routines_owner_hlc '
      'ON knowledge_routines(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_knowledge_routines_due '
      'ON knowledge_routines(owner_user_id, status, next_due_at) '
      'WHERE deleted_at IS NULL',
];
