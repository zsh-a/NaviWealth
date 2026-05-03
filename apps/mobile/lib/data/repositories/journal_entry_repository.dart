import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_outbox.dart';
import '../db/app_database.dart';
import '../domain/enums.dart';
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

  /// FIR-131 wave 3d — live stream of every non-deleted JE *with* its
  /// postings, materialised as a grouped `List<JournalEntryWithPostings>`.
  /// Drives the journal list page; subscribers re-render whenever the
  /// JE list changes (insert / update / soft-delete a JE).
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
    });
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
      await _enqueueJournal(
        opType: OpType.insert,
        rowId: jeId,
        fields: _journalInsertFields(domainEntry),
        stamp: stamp,
      );
      for (final p in domainPostings) {
        await _db.into(_db.postings).insert(_postingCompanion(p));
        await _enqueuePosting(
          opType: OpType.insert,
          rowId: p.id,
          fields: _postingInsertFields(p),
          stamp: stamp,
        );
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
      await _enqueueJournal(
        opType: OpType.delete,
        rowId: id,
        fields: null,
        stamp: stamp,
      );

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
        await _enqueuePosting(
          opType: OpType.delete,
          rowId: p.id,
          fields: null,
          stamp: stamp,
        );
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

  Map<String, Object?> _journalInsertFields(JournalEntry entry) => {
    'id': entry.id,
    'date': entry.date.toUtc().toIso8601String(),
    'settled_on': entry.settledOn?.toUtc().toIso8601String(),
    'narration': entry.narration,
    'payee': entry.payee,
    'flag': entry.flag.name,
    'tag_ids_json': jsonEncode(entry.tagIds),
    'owner_user_id': entry.sync.ownerUserId,
    'updated_at': entry.sync.updatedAt.toUtc().toIso8601String(),
    'updated_by_device': entry.sync.updatedByDevice,
    'hlc': entry.sync.hlc.toString(),
  };

  Map<String, Object?> _postingInsertFields(Posting p) => {
    'id': p.id,
    'journal_entry_id': p.journalEntryId,
    'position': p.position,
    'account_id': p.accountId,
    'units': p.units.toString(),
    'unit': p.unit,
    'cost_per_unit': p.cost?.perUnit.toString(),
    'cost_currency': p.cost?.currency,
    'cost_lot_id': p.cost?.lotId,
    'cost_acquired_on': p.cost?.acquiredOn?.toUtc().toIso8601String(),
    'price_per_unit': p.price?.perUnit.toString(),
    'price_currency': p.price?.currency,
    'owner_user_id': p.sync.ownerUserId,
    'updated_at': p.sync.updatedAt.toUtc().toIso8601String(),
    'updated_by_device': p.sync.updatedByDevice,
    'hlc': p.sync.hlc.toString(),
  };

  Future<void> _enqueueJournal({
    required OpType opType,
    required String rowId,
    required Map<String, Object?>? fields,
    required MutationStamp stamp,
  }) => _enqueue(
    tableName: _journalTable,
    opType: opType,
    rowId: rowId,
    fields: fields,
    stamp: stamp,
  );

  Future<void> _enqueuePosting({
    required OpType opType,
    required String rowId,
    required Map<String, Object?>? fields,
    required MutationStamp stamp,
  }) => _enqueue(
    tableName: _postingsTable,
    opType: opType,
    rowId: rowId,
    fields: fields,
    stamp: stamp,
  );

  Future<void> _enqueue({
    required String tableName,
    required OpType opType,
    required String rowId,
    required Map<String, Object?>? fields,
    required MutationStamp stamp,
  }) async {
    final op = Op(
      opId: _uuid.v4(),
      tableName: tableName,
      rowId: rowId,
      opType: opType,
      fieldsDiff: fields,
      hlc: stamp.hlc,
      deviceId: stamp.deviceId,
    );
    await _outbox.enqueue(op);
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
