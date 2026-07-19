part of 'journal_entry_repository.dart';

mixin JournalEntryRepositoryReadMixin {
  AppDatabase get _db;

  /// Live stream of every non-deleted JE ordered by `(date DESC, id ASC)`.
  /// The trailing id sort is a stable tiebreaker so two events on the
  /// same calendar day always resolve to the same render order.
  Stream<List<JournalEntry>> watchAll() {
    final query = _db.select(_db.journalEntries)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id),
      ]);
    return query.watch().map(
      (rows) => rows.map(_journalToDomain).toList(growable: false),
    );
  }

  /// Resolves a single JE plus its (sorted) postings. Returns `null`
  /// when the id is unknown or the JE is tombstoned.
  Future<JournalEntryWithPostings?> getById(String id) async {
    final entryRow =
        await (_db.select(_db.journalEntries)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
    if (entryRow == null) return null;
    final postingRows =
        await (_db.select(_db.postings)
              ..where((t) => t.journalEntryId.equals(id))
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.position)]))
            .get();
    return JournalEntryWithPostings(
      entry: _journalToDomain(entryRow),
      postings: postingRows.map(_postingToDomain).toList(growable: false),
    );
  }

  /// Finds active journal entries carrying an exact domain tag.
  ///
  /// Tag JSON is decoded through [_journalToDomain] before matching so ids
  /// containing SQL wildcard or JSON punctuation cannot produce a partial
  /// match. This path is used by infrequent recovery actions, where a safe
  /// full scan is preferable to a fuzzy `LIKE` lookup.
  Future<List<JournalEntry>> findByTag(String tagId) async {
    final rows = await (_db.select(
      _db.journalEntries,
    )..where((t) => t.deletedAt.isNull())).get();
    return rows
        .map(_journalToDomain)
        .where((entry) => entry.tagIds.contains(tagId))
        .toList(growable: false);
  }

  /// Live stream of every non-deleted [Posting] for a single account,
  /// joined to its JE so callers can sort by trade date without a
  /// follow-up read. Drives the account-detail timeline / balance
  /// rollups.
  Stream<List<Posting>> watchPostingsByAccount(String accountId) {
    final query =
        _db.select(_db.postings).join([
            innerJoin(
              _db.journalEntries,
              _db.journalEntries.id.equalsExp(_db.postings.journalEntryId),
            ),
          ])
          ..where(_db.postings.accountId.equals(accountId))
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.journalEntries.deletedAt.isNull())
          ..orderBy([
            OrderingTerm(expression: _db.journalEntries.date),
            OrderingTerm(expression: _db.postings.position),
          ]);
    return query.watch().map(
      (rows) => rows
          .map((r) => _postingToDomain(r.readTable(_db.postings)))
          .toList(growable: false),
    );
  }

  /// Raw algebraic sum of every non-deleted posting on [accountId].
  ///
  /// This is only meaningful for single-unit accounts. For cash balances,
  /// prefer [balanceByAccountUnit] so security quantities on the same
  /// brokerage account are not added to fiat cash.
  Future<Decimal> balanceByAccount(String accountId) async {
    return _sumPostings(accountId: accountId);
  }

  /// Current balance for one concrete unit on [accountId].
  ///
  /// Examples:
  /// - cash balance: `accountId = brokerage cash account`, `unit = CNY`
  /// - security position in one account: `unit = cn_a:600519`
  Future<Decimal> balanceByAccountUnit(String accountId, String unit) async {
    return _sumPostings(accountId: accountId, unit: unit);
  }

  Future<Decimal> _sumPostings({
    required String accountId,
    String? unit,
  }) async {
    final query =
        _db.select(_db.postings).join([
            innerJoin(
              _db.journalEntries,
              _db.journalEntries.id.equalsExp(_db.postings.journalEntryId),
            ),
          ])
          ..where(_db.postings.accountId.equals(accountId))
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.journalEntries.deletedAt.isNull());
    if (unit != null) {
      query.where(_db.postings.unit.equals(unit));
    }
    final rows = await query.get();
    var sum = Decimal.zero;
    for (final row in rows) {
      sum += row.readTable(_db.postings).units;
    }
    return sum;
  }

  /// Live stream of per-unit balances across **every** account in one go.
  ///
  /// Returned shape: `{ accountId → { unit → runningTotal } }`. Zero-sum
  /// legs are dropped so the UI doesn't render a "USD 0.00" row for a
  /// closed currency leg. Used by the Accounts Hub multi-currency rows
  /// — keeping it as a single bulk stream avoids O(N) per-account
  /// subscriptions when the user has dozens of accounts.
  Stream<Map<String, Map<String, Decimal>>> watchBalancesByUnit() {
    final query =
        _db.select(_db.postings).join([
            innerJoin(
              _db.journalEntries,
              _db.journalEntries.id.equalsExp(_db.postings.journalEntryId),
            ),
          ])
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.journalEntries.deletedAt.isNull());
    return query.watch().map((rows) {
      final out = <String, Map<String, Decimal>>{};
      for (final row in rows) {
        final p = row.readTable(_db.postings);
        final byUnit = out.putIfAbsent(p.accountId, () => <String, Decimal>{});
        byUnit[p.unit] = (byUnit[p.unit] ?? Decimal.zero) + p.units;
      }
      // Drop zero-sum legs.
      for (final byUnit in out.values) {
        byUnit.removeWhere((_, v) => v == Decimal.zero);
      }
      return out;
    });
  }

  /// Live stream of expense entries materialised from the
  /// journal. Each row is a JE whose expense-leg posting sits on an
  /// `accounts.category = 'expense'` account. The result is shaped as
  /// [Expense] so existing report / list UI can consume it without
  /// changing their domain model.
  Stream<List<Expense>> watchExpenses() {
    final query =
        _db.select(_db.journalEntries).join([
            innerJoin(
              _db.postings,
              _db.postings.journalEntryId.equalsExp(_db.journalEntries.id),
            ),
            innerJoin(
              _db.accounts,
              _db.accounts.id.equalsExp(_db.postings.accountId),
            ),
          ])
          ..where(_db.accounts.category.equals(AccountSide.expense.name))
          ..where(_db.journalEntries.deletedAt.isNull())
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.accounts.deletedAt.isNull())
          ..orderBy([
            OrderingTerm(
              expression: _db.journalEntries.date,
              mode: OrderingMode.desc,
            ),
          ]);
    return query.watch().asyncMap((rows) async {
      final entryIds = {
        for (final row in rows) row.readTable(_db.journalEntries).id,
      };
      final postingsByEntryId = <String, List<PostingRow>>{};
      if (entryIds.isNotEmpty) {
        final postings =
            await (_db.select(_db.postings)
                  ..where((t) => t.deletedAt.isNull())
                  ..where((t) => t.journalEntryId.isIn(entryIds)))
                .get();
        for (final posting in postings) {
          postingsByEntryId
              .putIfAbsent(posting.journalEntryId, () => <PostingRow>[])
              .add(posting);
        }
      }
      final out = <Expense>[];
      for (final row in rows) {
        final jeRow = row.readTable(_db.journalEntries);
        final postingRow = row.readTable(_db.postings);
        final e = _postingToExpense(
          jeRow,
          postingRow,
          postingsByEntryId[jeRow.id] ?? const <PostingRow>[],
        );
        if (e != null) out.add(e);
      }
      return out;
    });
  }
}
