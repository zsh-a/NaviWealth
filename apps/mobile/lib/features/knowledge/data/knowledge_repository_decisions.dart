part of 'knowledge_repository.dart';

mixin KnowledgeDecisionsRepositoryMixin {
  AppDatabase get _db;

  Future<void> _upsertAndEnqueue<R>(
    TableInfo<Table, R> table,
    Insertable<R> companion, {
    required String tableName,
    required String rowId,
  });

  Stream<List<KnowledgeDecision>> watchDecisions({
    required String ownerUserId,
    int? limit,
  }) {
    final q = _db.select(_db.knowledgeDecisions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.decidedAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => rows.map(knowledgeDecisionFromRow).toList());
  }

  Future<List<KnowledgeDecision>> listDecisions({
    required String ownerUserId,
    Set<DecisionStatus>? statuses,
    int limit = 200,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgeDecisions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull());
    if (statuses != null && statuses.isNotEmpty) {
      q.where(
        (t) =>
            t.status.isIn(statuses.map((s) => s.wire).toList(growable: false)),
      );
    }
    q
      ..orderBy([
        (t) => OrderingTerm(expression: t.decidedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgeDecisionFromRow).toList();
  }

  Future<List<KnowledgeDecision>> listDueReviews({
    required String ownerUserId,
    required DateTime asOf,
    int limit = 100,
  }) async {
    final rows = await _dueReviewsQuery(
      ownerUserId: ownerUserId,
      asOf: asOf,
      limit: limit,
    ).get();
    return rows.map(knowledgeDecisionFromRow).toList();
  }

  /// Complete due work, independent of the recent Library browse window.
  Stream<List<KnowledgeDecision>> watchDueReviews({
    required String ownerUserId,
    required DateTime asOf,
  }) => _dueReviewsQuery(
    ownerUserId: ownerUserId,
    asOf: asOf,
  ).watch().map((rows) => rows.map(knowledgeDecisionFromRow).toList());

  Selectable<KnowledgeDecisionRow> _dueReviewsQuery({
    required String ownerUserId,
    required DateTime asOf,
    int? limit,
  }) {
    final q = _db.select(_db.knowledgeDecisions)
      ..where((t) => t.ownerUserId.equals(ownerUserId) & t.deletedAt.isNull())
      ..where(
        (t) => t.status.isIn([
          DecisionStatus.active.wire,
          DecisionStatus.draft.wire,
          DecisionStatus.paused.wire,
        ]),
      )
      ..where((t) => t.reviewDate.isSmallerOrEqualValue(asOf))
      ..orderBy([
        (t) => OrderingTerm(expression: t.reviewDate),
        (t) => OrderingTerm(expression: t.id),
      ]);
    if (limit != null) q.limit(limit);
    return q;
  }

  Future<KnowledgeDecision?> findDecision({
    required String ownerUserId,
    required String id,
  }) async {
    final row =
        await (_db.select(_db.knowledgeDecisions)..where(
              (t) => t.id.equals(id) & t.ownerUserId.equals(ownerUserId),
            ))
            .getSingleOrNull();
    return row == null ? null : knowledgeDecisionFromRow(row);
  }

  Future<void> upsertDecision(KnowledgeDecision d) async {
    await _upsertAndEnqueue(
      _db.knowledgeDecisions,
      knowledgeDecisionCompanion(d),
      tableName: _knowledgeDecisionsTable,
      rowId: d.id,
    );
  }
}
