import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/persistence/app_database.dart';
import '../../core/sync/op_outbox.dart';
import '../domain/entry_kind.dart';
import '../domain/enums.dart';
import '../domain/expense.dart';
import '../domain/invariants.dart';
import '../domain/journal_entry.dart';
import '../domain/posting.dart';
import '../domain/sync_meta.dart';
import 'mutation_context.dart';

/// FIR-130 — Drift DAO for `journal_entries` + `postings`. Models a JE
/// and its postings as one logical unit: every public mutation lives
/// inside a single Drift transaction that writes the JE row, the
/// posting rows, and queues the corresponding outbox `Op`s atomically.
///
/// Balance enforcement: every `create` / `replacePostings` call routes
/// through [evaluateEntryBalance]. A non-balanced JE throws
/// [JournalEntryUnbalancedException]; the writer never commits a half-
/// balanced ledger.
///
/// What this repository deliberately does NOT do:
///   - Build the legs for a buy / sell / transfer (that's the FIR-131
///     `JournalEntryBuilders` surface — this DAO is the persistence
///     backend the builders sit on top of).
///   - Run cost-basis selection (FIFO / LIFO) — `cost.lotId` is taken
///     verbatim from the caller.
///   - Refresh derived holdings; readers query postings directly.
class JournalEntryRepository {
  JournalEntryRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    required FxRateSource fxRateSource,
    required String baseCurrency,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _fx = fxRateSource,
       _baseCurrency = baseCurrency,
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final FxRateSource _fx;
  final String _baseCurrency;
  final Uuid _uuid;

  static const String _journalTable = 'journal_entries';
  static const String _postingsTable = 'postings';

  // ---------- Reads ----------

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

  /// Live stream of every non-deleted JE *with* its postings,
  /// materialised as a grouped `List<JournalEntryWithPostings>`.
  /// Drives the journal list page; subscribers re-render whenever
  /// the JE list changes (insert / update / soft-delete a JE).
  ///
  /// Implementation: rides on top of the JE-list stream and pulls the
  /// matching postings in a single `WHERE journal_entry_id IN (...)`
  /// query per emission. This means a JE-write atomically (which is
  /// the FIR-130 `JournalEntryRepository.create` contract — every
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
      if (rows.isEmpty) break;

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

  /// FIR-132 — live stream of expense entries materialised from the
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
    return query.watch().map((rows) {
      final out = <Expense>[];
      for (final row in rows) {
        final jeRow = row.readTable(_db.journalEntries);
        final postingRow = row.readTable(_db.postings);
        final e = _postingToExpense(jeRow, postingRow);
        if (e != null) out.add(e);
      }
      return out;
    });
  }

  /// Maps a JE + its expense-leg posting to an [Expense] domain object.
  Expense? _postingToExpense(JournalEntryRow jeRow, PostingRow postingRow) {
    final tagIds = (jsonDecode(jeRow.tagIdsJson) as List<dynamic>)
        .cast<String>();
    return Expense(
      id: jeRow.id,
      expenseAccountId: postingRow.accountId,
      amount: postingRow.units.abs(),
      currency: postingRow.unit,
      tradeDate: jeRow.date,
      tags: tagIds,
      note: jeRow.narration,
      sync: SyncMeta(
        ownerUserId: jeRow.ownerUserId,
        updatedAt: jeRow.updatedAt,
        updatedByDevice: jeRow.updatedByDevice,
        hlc: jeRow.hlc,
        deletedAt: jeRow.deletedAt,
      ),
    );
  }

  // ---------- Writes ----------

  /// Inserts a new JE plus its postings as one Drift transaction. The
  /// caller passes lightweight drafts ([JournalEntryDraft] / [PostingDraft])
  /// without sync metadata — the repo stamps them.
  ///
  /// Throws [JournalEntryUnbalancedException] before touching the DB if
  /// the postings don't balance.
  Future<JournalEntryWithPostings> create({
    required JournalEntryDraft entry,
    required List<PostingDraft> postings,
  }) async {
    if (postings.isEmpty) {
      throw const JournalEntryUnbalancedException(
        'Cannot create journal entry with zero postings.',
      );
    }
    final stamp = await _stamper.stamp();
    final jeId = entry.id ?? _uuid.v4();
    final domainEntry = JournalEntry(
      id: jeId,
      date: entry.date,
      settledOn: entry.settledOn,
      narration: entry.narration,
      payee: entry.payee,
      tagIds: List.unmodifiable(entry.tagIds),
      flag: entry.flag,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    final domainPostings = <Posting>[];
    for (var i = 0; i < postings.length; i++) {
      final draft = postings[i];
      domainPostings.add(
        Posting(
          id: draft.id ?? _uuid.v4(),
          journalEntryId: jeId,
          position: draft.position ?? i,
          accountId: draft.accountId,
          units: draft.units,
          unit: draft.unit,
          cost: draft.cost,
          price: draft.price,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    }

    final report = evaluateEntryBalance(
      entry: domainEntry,
      postings: domainPostings,
      fx: _fx,
      baseCurrency: _baseCurrency,
    );
    if (!report.isBalanced) {
      throw JournalEntryUnbalancedException.fromReport(report);
    }

    await _db.transaction(() async {
      await _db.into(_db.journalEntries).insert(_journalCompanion(domainEntry));
      await _outbox.enqueue(table: _journalTable, rowId: jeId);
      for (final p in domainPostings) {
        await _db.into(_db.postings).insert(_postingCompanion(p));
        await _outbox.enqueue(table: _postingsTable, rowId: p.id);
      }
    });
    return JournalEntryWithPostings(
      entry: domainEntry,
      postings: domainPostings,
    );
  }

  /// Atomically replace a JE's postings + (some of) its envelope
  /// fields. The semantics: in one Drift transaction,
  ///
  ///   1. update the JE row (date / settledOn / narration / payee /
  ///      flag / tagIds) with a fresh sync stamp,
  ///   2. soft-delete every still-live posting tied to this JE,
  ///   3. insert the replacement postings.
  ///
  /// Sync ops queued: a JE update + N posting deletes + M posting
  /// inserts, all under the same HLC tick. Peers replay the entire
  /// batch in one shot so the JE is never observed mid-replacement.
  ///
  /// Throws [JournalEntryUnbalancedException] before touching the DB
  /// if the new postings don't balance — same contract as [create].
  /// Throws [StateError] when [id] doesn't refer to an existing
  /// (non-tombstoned) JE.
  Future<JournalEntryWithPostings> replacePostings({
    required String id,
    required JournalEntryDraft entry,
    required List<PostingDraft> postings,
  }) async {
    if (postings.isEmpty) {
      throw const JournalEntryUnbalancedException(
        'Cannot replace journal entry with zero postings.',
      );
    }
    final existingRow =
        await (_db.select(_db.journalEntries)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
    if (existingRow == null) {
      throw StateError(
        'replacePostings called on missing or tombstoned JE id=$id',
      );
    }

    final stamp = await _stamper.stamp();
    final domainEntry = JournalEntry(
      id: id,
      date: entry.date,
      settledOn: entry.settledOn,
      narration: entry.narration,
      payee: entry.payee,
      tagIds: List.unmodifiable(entry.tagIds),
      flag: entry.flag,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    final domainPostings = <Posting>[];
    for (var i = 0; i < postings.length; i++) {
      final draft = postings[i];
      domainPostings.add(
        Posting(
          id: draft.id ?? _uuid.v4(),
          journalEntryId: id,
          position: draft.position ?? i,
          accountId: draft.accountId,
          units: draft.units,
          unit: draft.unit,
          cost: draft.cost,
          price: draft.price,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    }

    final report = evaluateEntryBalance(
      entry: domainEntry,
      postings: domainPostings,
      fx: _fx,
      baseCurrency: _baseCurrency,
    );
    if (!report.isBalanced) {
      throw JournalEntryUnbalancedException.fromReport(report);
    }

    await _db.transaction(() async {
      // 1. JE envelope update.
      final jeUpdate = JournalEntriesCompanion(
        date: Value(domainEntry.date),
        settledOn: Value(domainEntry.settledOn),
        narration: Value(domainEntry.narration),
        payee: Value(domainEntry.payee),
        flag: Value(domainEntry.flag),
        tagIdsJson: Value(jsonEncode(domainEntry.tagIds)),
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
      );
      await (_db.update(
        _db.journalEntries,
      )..where((t) => t.id.equals(id))).write(jeUpdate);
      await _outbox.enqueue(table: _journalTable, rowId: id);

      // 2. Tombstone the existing postings + queue delete ops.
      final oldPostingRows =
          await (_db.select(_db.postings)
                ..where((t) => t.journalEntryId.equals(id))
                ..where((t) => t.deletedAt.isNull()))
              .get();
      final tombstone = PostingsCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );
      await (_db.update(_db.postings)
            ..where((t) => t.journalEntryId.equals(id))
            ..where((t) => t.deletedAt.isNull()))
          .write(tombstone);
      for (final p in oldPostingRows) {
        await _outbox.enqueue(table: _postingsTable, rowId: p.id);
      }

      // 3. Insert the replacements.
      for (final p in domainPostings) {
        await _db.into(_db.postings).insert(_postingCompanion(p));
        await _outbox.enqueue(table: _postingsTable, rowId: p.id);
      }
    });

    return JournalEntryWithPostings(
      entry: domainEntry,
      postings: domainPostings,
    );
  }

  /// Soft-delete the JE plus all its postings. Tombstones cascade in
  /// the same transaction so a partially-tombstoned ledger never
  /// surfaces from a crash mid-delete.
  Future<void> softDelete(String id) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final jeUpdate = JournalEntriesCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );
      await (_db.update(
        _db.journalEntries,
      )..where((t) => t.id.equals(id))).write(jeUpdate);
      await _outbox.enqueue(table: _journalTable, rowId: id);

      final postingRows =
          await (_db.select(_db.postings)
                ..where((t) => t.journalEntryId.equals(id))
                ..where((t) => t.deletedAt.isNull()))
              .get();
      final postingUpdate = PostingsCompanion(
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
        deletedAt: Value(stamp.now),
      );
      await (_db.update(_db.postings)
            ..where((t) => t.journalEntryId.equals(id))
            ..where((t) => t.deletedAt.isNull()))
          .write(postingUpdate);
      for (final p in postingRows) {
        await _outbox.enqueue(table: _postingsTable, rowId: p.id);
      }
    });
  }

  // ---------- Companion / op helpers ----------

  JournalEntriesCompanion _journalCompanion(JournalEntry entry) {
    return JournalEntriesCompanion.insert(
      id: entry.id,
      date: entry.date,
      settledOn: Value(entry.settledOn),
      narration: entry.narration,
      payee: Value(entry.payee),
      flag: Value(entry.flag),
      tagIdsJson: Value(jsonEncode(entry.tagIds)),
      ownerUserId: entry.sync.ownerUserId,
      updatedAt: entry.sync.updatedAt,
      updatedByDevice: entry.sync.updatedByDevice,
      hlc: entry.sync.hlc,
    );
  }

  PostingsCompanion _postingCompanion(Posting p) {
    return PostingsCompanion.insert(
      id: p.id,
      journalEntryId: p.journalEntryId,
      position: p.position,
      accountId: p.accountId,
      units: p.units,
      unit: p.unit,
      costPerUnit: Value(p.cost?.perUnit),
      costCurrency: Value(p.cost?.currency),
      costLotId: Value(p.cost?.lotId),
      costAcquiredOn: Value(p.cost?.acquiredOn),
      pricePerUnit: Value(p.price?.perUnit),
      priceCurrency: Value(p.price?.currency),
      ownerUserId: p.sync.ownerUserId,
      updatedAt: p.sync.updatedAt,
      updatedByDevice: p.sync.updatedByDevice,
      hlc: p.sync.hlc,
    );
  }

  // ---------- Row → domain ----------

  JournalEntry _journalToDomain(JournalEntryRow row) {
    final tagIds = (jsonDecode(row.tagIdsJson) as List<dynamic>).cast<String>();
    return JournalEntry(
      id: row.id,
      date: row.date,
      settledOn: row.settledOn,
      narration: row.narration,
      payee: row.payee,
      tagIds: List.unmodifiable(tagIds),
      flag: row.flag,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );
  }

  Posting _postingToDomain(PostingRow row) {
    Cost? cost;
    if (row.costPerUnit != null && row.costCurrency != null) {
      cost = Cost(
        perUnit: row.costPerUnit!,
        currency: row.costCurrency!,
        lotId: row.costLotId,
        acquiredOn: row.costAcquiredOn,
      );
    }
    Price? price;
    if (row.pricePerUnit != null && row.priceCurrency != null) {
      price = Price(perUnit: row.pricePerUnit!, currency: row.priceCurrency!);
    }
    return Posting(
      id: row.id,
      journalEntryId: row.journalEntryId,
      position: row.position,
      accountId: row.accountId,
      units: row.units,
      unit: row.unit,
      cost: cost,
      price: price,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );
  }
}

class ActivityFeedCursor {
  const ActivityFeedCursor({required this.date, required this.id});

  final DateTime date;
  final String id;
}

class ActivityFeedReadPage {
  const ActivityFeedReadPage({required this.entries, required this.hasMore});

  final List<JournalEntryWithPostings> entries;
  final bool hasMore;
}

/// Lightweight draft: callers describe the JE without having to mint
/// ids or stamp sync metadata. The repo fills both before the row hits
/// SQLite.
class JournalEntryDraft {
  const JournalEntryDraft({
    this.id,
    required this.date,
    this.settledOn,
    required this.narration,
    this.payee,
    this.tagIds = const <String>[],
    this.flag = EntryFlag.confirmed,
  });

  final String? id;
  final DateTime date;
  final DateTime? settledOn;
  final String narration;
  final String? payee;
  final List<String> tagIds;
  final EntryFlag flag;
}

class PostingDraft {
  const PostingDraft({
    this.id,
    this.position,
    required this.accountId,
    required this.units,
    required this.unit,
    this.cost,
    this.price,
  });

  final String? id;
  final int? position;
  final String accountId;
  final Decimal units;
  final String unit;
  final Cost? cost;
  final Price? price;
}

/// Materialised JE — the entry plus its postings in canonical order.
class JournalEntryWithPostings {
  const JournalEntryWithPostings({required this.entry, required this.postings});

  final JournalEntry entry;
  final List<Posting> postings;
}

/// Thrown by [JournalEntryRepository] when a JE write would violate the
/// SUM(weight) = 0 invariant. Carries the structured report so callers
/// can render targeted errors instead of a generic "won't save" toast.
class JournalEntryUnbalancedException implements Exception {
  const JournalEntryUnbalancedException(this.message, {this.report});

  factory JournalEntryUnbalancedException.fromReport(
    JournalEntryBalanceReport report,
  ) {
    final summary = report.problems.isEmpty
        ? 'Σ(weight) = ${report.totalBaseWeight} '
              'exceeds tolerance ±${report.tolerance}.'
        : report.problems.map((p) => p.message).join('; ');
    return JournalEntryUnbalancedException(summary, report: report);
  }

  final String message;
  final JournalEntryBalanceReport? report;

  @override
  String toString() => 'JournalEntryUnbalancedException: $message';
}
