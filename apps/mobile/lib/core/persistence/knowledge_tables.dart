/// KnowledgeOS Drift tables (`docs/knowledgeos-domain.md` §3 + §9).
///
/// Six tables — Notes / Principles / Assumptions / Decisions / Concepts /
/// Experiments. Memory is *not* a separate table here: per §3 it reuses
/// Memory Layer `kind='semantic'` records directly.
///
/// All tables wear [SyncableTable] and carry the `know:` row family
/// prefix on the wire (see `core/sync/domain_prefix.dart` and
/// `docs/lifeos-shell.md` §8). The local table names stay unprefixed —
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
];
