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
  }) {
    final trigger = _db
        .customSelect(
          '''
      SELECT
        (SELECT COUNT(*) FROM journal_entries WHERE deleted_at IS NULL) AS je_count,
        (SELECT COUNT(*) FROM postings WHERE deleted_at IS NULL) AS posting_count
      ''',
          readsFrom: {_db.journalEntries, _db.postings, _db.accounts},
        )
        .watch();
    return trigger.asyncMap(
      (_) => queryActivityFeed(
        from: from,
        to: to,
        accountIds: accountIds,
        kinds: kinds,
        accountCategories: accountCategories,
        pageSize: pageSize,
      ),
    );
  }

  Future<ActivityFeedReadPage> queryActivityFeed({
    DateTime? from,
    DateTime? to,
    Set<String> accountIds = const <String>{},
    Set<EntryKind> kinds = const <EntryKind>{},
    required Map<String, AccountSide> accountCategories,
    int pageSize = 50,
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
  }) async {
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
    variables.add(Variable<int>(limit));
    final rows = await _db
        .customSelect(
          '''
          SELECT je.*
          FROM journal_entries je
          WHERE ${where.join(' AND ')}
          ORDER BY je.date DESC, je.id ASC
          LIMIT ?
          ''',
          variables: variables,
          readsFrom: {_db.journalEntries, _db.postings},
        )
        .get();
    return rows.map((row) => _db.journalEntries.map(row.data)).toList();
  }
}
