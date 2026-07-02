import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:uuid/uuid.dart';

part 'journal_entry_repository_activity_feed.dart';
part 'journal_entry_repository_mappers.dart';
part 'journal_entry_repository_models.dart';

/// Drift DAO for `journal_entries` + `postings`. Models a JE
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
///   - Build the legs for a buy / sell / transfer (that's the
///     `JournalEntryBuilders` surface — this DAO is the persistence
///     backend the builders sit on top of).
///   - Run cost-basis selection (FIFO / LIFO) — `cost.lotId` is taken
///     verbatim from the caller.
///   - Refresh derived holdings; readers query postings directly.
class JournalEntryRepository with JournalEntryRepositoryActivityFeedMixin {
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

  @override
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
  @override
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
}
