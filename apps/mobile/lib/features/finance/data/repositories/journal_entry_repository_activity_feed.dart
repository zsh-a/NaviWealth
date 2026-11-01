part of 'journal_entry_repository.dart';

mixin JournalEntryRepositoryActivityFeedMixin {
  AppDatabase get _db;

  Stream<List<JournalEntry>> watchAll();

  /// Live stream of every non-deleted JE *with* its postings,
  /// materialised as a grouped `List<JournalEntryWithPostings>`.
  /// Drives the journal list page; subscribers re-render whenever
  /// the JE list changes (insert / update / soft-delete a JE).
  ///
  /// Implementation: rides on top of the JE-list stream and pulls the
  /// matching postings in a single `WHERE journal_entry_id IN (...)`
  /// query per emission. This means a JE-write atomically (which is
  /// the `JournalEntryRepository.create` contract — every
  /// posting batch ships with its parent JE in one transaction) hits
  /// the consumer with a fresh snapshot. Posting-only mutations (e.g.
  /// a sync-borne posting update without its JE row changing) won't
  /// re-emit by themselves; we accept that today because the local
  /// write path always co-mutates both. A follow-up PR can pair the
  /// JE watch with a posting-watch trigger if cross-device sync
  /// surfaces lag here.
  Stream<List<JournalEntryWithPostings>> watchAllWithPostings() {
    return watchAll().asyncMap((entries) async {
      if (entries.isEmpty) return const <JournalEntryWithPostings>[];
      return _entriesWithPostings(entries);
    });
  }

  /// Activity-feed read model: paged, newest-first, and backed by SQL
  /// predicates for date/account filters. Kind filters are classified from
  /// the fetched postings and account categories; when kind filtering is
  /// active the query advances via a `(date DESC, id ASC)` keyset cursor in
  /// bounded batches until it fills [pageSize] or exhausts the source rows.
  Stream<ActivityFeedReadPage> watchActivityFeed({
    DateTime? from,
    DateTime? to,
    Set<String> accountIds = const <String>{},
    Set<EntryKind> kinds = const <EntryKind>{},
    required Map<String, AccountSide> accountCategories,
    int pageSize = 50,
    String searchText = '',
  }) {
    return _watchActivitySource().asyncMap(
      (_) => queryActivityFeed(
        from: from,
        to: to,
        accountIds: accountIds,
        kinds: kinds,
        accountCategories: accountCategories,
        pageSize: pageSize,
        searchText: searchText,
      ),
    );
  }

  Stream<int> watchActivityFeedCount({
    DateTime? from,
    DateTime? to,
    Set<String> accountIds = const <String>{},
    Set<EntryKind> kinds = const <EntryKind>{},
    required Map<String, AccountSide> accountCategories,
    String searchText = '',
  }) => _watchActivitySource().asyncMap(
    (_) => queryActivityFeedCount(
      from: from,
      to: to,
      accountIds: accountIds,
      kinds: kinds,
      accountCategories: accountCategories,
      searchText: searchText,
    ),
  );

  Stream<List<QueryRow>> _watchActivitySource() => _db
      .customSelect(
        '''
      SELECT
        (SELECT COUNT(*) FROM journal_entries WHERE deleted_at IS NULL) AS je_count,
        (SELECT COUNT(*) FROM postings WHERE deleted_at IS NULL) AS posting_count
      ''',
        readsFrom: {_db.journalEntries, _db.postings, _db.accounts},
      )
      .watch();

  Future<ActivityFeedReadPage> queryActivityFeed({
    DateTime? from,
    DateTime? to,
    Set<String> accountIds = const <String>{},
    Set<EntryKind> kinds = const <EntryKind>{},
    required Map<String, AccountSide> accountCategories,
    int pageSize = 50,
    String searchText = '',
  }) async {
    final limit = pageSize.clamp(1, 500).toInt();
    final batchSize = kinds.isEmpty ? limit + 1 : limit.clamp(50, 200);
    final accepted = <JournalEntryWithPostings>[];
    ActivityFeedCursor? cursor;
    var sourceExhausted = false;

    while (accepted.length < limit + 1 && !sourceExhausted) {
      final rows = await _queryActivityEntryRows(
        from: from,
        to: to,
        accountIds: accountIds,
        searchText: searchText,
        after: cursor,
        limit: batchSize,
      );
      if (rows.isEmpty) {
        sourceExhausted = true;
        break;
      }

      final entries = rows.map(_journalToDomain).toList(growable: false);
      final page = await _entriesWithPostings(entries);
      for (final item in page) {
        if (kinds.isNotEmpty) {
          final classification = classifyEntryKind(
            postings: item.postings,
            resolveCategory: (id) => accountCategories[id],
          );
          if (!kinds.contains(classification.kind)) {
            continue;
          }
        }
        accepted.add(item);
        if (accepted.length > limit) break;
      }

      if (rows.length < batchSize) {
        sourceExhausted = true;
      }
      final last = rows.last;
      cursor = ActivityFeedCursor(date: last.date, id: last.id);
    }

    final hasMore = accepted.length > limit;
    if (hasMore) accepted.removeLast();
    return ActivityFeedReadPage(
      entries: accepted,
      hasMore: hasMore || !sourceExhausted,
    );
  }

  /// Exact preview of the same predicates used by the paged feed. Kind is a
  /// domain-derived classification, so count it in bounded keyset batches.
  Future<int> queryActivityFeedCount({
    DateTime? from,
    DateTime? to,
    Set<String> accountIds = const <String>{},
    Set<EntryKind> kinds = const <EntryKind>{},
    required Map<String, AccountSide> accountCategories,
    String searchText = '',
  }) async {
    if (kinds.isEmpty) {
      final predicate = _activityFeedPredicate(
        from: from,
        to: to,
        accountIds: accountIds,
        searchText: searchText,
      );
      final row = await _db
          .customSelect(
            'SELECT COUNT(*) AS count FROM journal_entries je WHERE ${predicate.sql}',
            variables: predicate.variables,
            readsFrom: {_db.journalEntries, _db.postings, _db.accounts},
          )
          .getSingle();
      return row.read<int>('count');
    }
    var count = 0;
    ActivityFeedCursor? cursor;
    const batchSize = 200;
    while (true) {
      final rows = await _queryActivityEntryRows(
        from: from,
        to: to,
        accountIds: accountIds,
        searchText: searchText,
        after: cursor,
        limit: batchSize,
      );
      final entries = await _entriesWithPostings(
        rows.map(_journalToDomain).toList(growable: false),
      );
      count += entries
          .where(
            (item) => kinds.contains(
              classifyEntryKind(
                postings: item.postings,
                resolveCategory: (id) => accountCategories[id],
              ).kind,
            ),
          )
          .length;
      if (rows.length < batchSize) return count;
      final last = rows.last;
      cursor = ActivityFeedCursor(date: last.date, id: last.id);
    }
  }

  Future<List<JournalEntryWithPostings>> _entriesWithPostings(
    List<JournalEntry> entries,
  ) async {
    if (entries.isEmpty) return const <JournalEntryWithPostings>[];
    final ids = entries.map((e) => e.id).toList(growable: false);
    final postingRows =
        await (_db.select(_db.postings)
              ..where((t) => t.journalEntryId.isIn(ids))
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.position)]))
            .get();
    final byEntry = <String, List<Posting>>{};
    for (final p in postingRows) {
      byEntry
          .putIfAbsent(p.journalEntryId, () => <Posting>[])
          .add(_postingToDomain(p));
    }
    return entries
        .map(
          (e) => JournalEntryWithPostings(
            entry: e,
            postings: byEntry[e.id] ?? const <Posting>[],
          ),
        )
        .toList(growable: false);
  }

  Future<List<JournalEntryRow>> _queryActivityEntryRows({
    DateTime? from,
    DateTime? to,
    Set<String> accountIds = const <String>{},
    ActivityFeedCursor? after,
    required int limit,
    String searchText = '',
  }) async {
    final predicate = _activityFeedPredicate(
      from: from,
      to: to,
      accountIds: accountIds,
      after: after,
      searchText: searchText,
    );
    final rows = await _db
        .customSelect(
          '''
      SELECT je.* FROM journal_entries je
      WHERE ${predicate.sql}
      ORDER BY je.date DESC, je.id ASC LIMIT ?
      ''',
          variables: [...predicate.variables, Variable<int>(limit)],
          readsFrom: {_db.journalEntries, _db.postings, _db.accounts},
        )
        .get();
    return rows.map((row) => _db.journalEntries.map(row.data)).toList();
  }

  ({String sql, List<Variable> variables}) _activityFeedPredicate({
    DateTime? from,
    DateTime? to,
    Set<String> accountIds = const <String>{},
    ActivityFeedCursor? after,
    String searchText = '',
  }) {
    final where = <String>['je.deleted_at IS NULL'];
    final variables = <Variable>[];
    if (from != null) {
      where.add('je.date >= ?');
      variables.add(Variable<DateTime>(from));
    }
    if (to != null) {
      where.add('je.date < ?');
      variables.add(Variable<DateTime>(to));
    }
    if (after != null) {
      where.add('(je.date < ? OR (je.date = ? AND je.id > ?))');
      variables
        ..add(Variable<DateTime>(after.date))
        ..add(Variable<DateTime>(after.date))
        ..add(Variable<String>(after.id));
    }
    if (accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(', ');
      where.add('''
        EXISTS (
          SELECT 1 FROM postings p
          WHERE p.journal_entry_id = je.id
            AND p.deleted_at IS NULL
            AND p.account_id IN ($placeholders)
        )
      ''');
      variables.addAll(accountIds.map((id) => Variable<String>(id)));
    }
    final needle = searchText.trim().toLowerCase();
    if (needle.isNotEmpty) {
      // instr treats %, _ and backslashes literally, matching the search UI.
      where.add('''(
        instr(lower(je.narration), ?) > 0 OR
        instr(lower(coalesce(je.payee, '')), ?) > 0 OR
        EXISTS (
          SELECT 1 FROM postings p JOIN accounts a ON a.id = p.account_id
          WHERE p.journal_entry_id = je.id AND p.deleted_at IS NULL
            AND a.deleted_at IS NULL AND instr(lower(a.name), ?) > 0
        )
      )''');
      variables.addAll(List.generate(3, (_) => Variable<String>(needle)));
    }
    return (sql: where.join(' AND '), variables: variables);
  }
}
