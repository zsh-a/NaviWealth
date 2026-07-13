import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

import '../domain/models/lot.dart';

final class LedgerLotMovement {
  const LedgerLotMovement({required this.posting, required this.date});

  final PostingRow posting;
  final DateTime date;
}

/// Single ledger-backed source of truth for live investment lots.
final class LedgerLotReader {
  const LedgerLotReader(this._db);

  final AppDatabase _db;

  bool isBoundTo(AppDatabase database) => identical(_db, database);

  Future<List<Lot>> lotsAt({
    required String ownerUserId,
    required String accountId,
    required String assetId,
    required DateTime asOf,
  }) => _lotsAt(
    ownerUserId: ownerUserId,
    accountId: accountId,
    assetId: assetId,
    asOf: asOf,
  );

  Future<List<Lot>> allLotsAt({
    required String ownerUserId,
    required DateTime asOf,
  }) => _lotsAt(ownerUserId: ownerUserId, asOf: asOf);

  Future<List<LedgerLotMovement>> allMovementsThrough({
    required String ownerUserId,
    required DateTime asOf,
  }) => _movementsThrough(ownerUserId: ownerUserId, asOf: asOf);

  /// Replays all requested instants from a single ordered movement query.
  /// Each movement is applied once even when a chart requests hundreds of
  /// samples.
  Future<Map<DateTime, List<Lot>>> allLotsAtSamples({
    required String ownerUserId,
    required Iterable<DateTime> dates,
  }) async {
    final sorted = dates.map((date) => date.toUtc()).toSet().toList()..sort();
    if (sorted.isEmpty) return const {};
    final movements = await _movementsThrough(
      ownerUserId: ownerUserId,
      asOf: sorted.last,
    );
    final lots = <Lot>[];
    final result = <DateTime, List<Lot>>{};
    var movementIndex = 0;
    for (final date in sorted) {
      while (movementIndex < movements.length &&
          !movements[movementIndex].date.isAfter(date)) {
        _applyMovement(lots, movements[movementIndex]);
        movementIndex += 1;
      }
      result[date] = List<Lot>.unmodifiable(List<Lot>.of(lots));
    }
    return Map<DateTime, List<Lot>>.unmodifiable(result);
  }

  Future<DateTime?> latestRelevantMovementAt({
    required String ownerUserId,
    required String accountId,
    required String assetId,
  }) async {
    _requireIdentity(ownerUserId, accountId: accountId, assetId: assetId);
    final query =
        _livePostingQuery(
            ownerUserId: ownerUserId,
            accountId: accountId,
            assetId: assetId,
          )
          ..orderBy([
            OrderingTerm.desc(_db.journalEntries.date),
            OrderingTerm.desc(_db.postings.position),
            OrderingTerm.desc(_db.postings.id),
          ])
          ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.readTable(_db.journalEntries).date.toUtc();
  }

  Future<Decimal> currentBalance({
    required String ownerUserId,
    required String accountId,
    required String assetId,
  }) async {
    _requireIdentity(ownerUserId, accountId: accountId, assetId: assetId);
    final rows = await _livePostingQuery(
      ownerUserId: ownerUserId,
      accountId: accountId,
      assetId: assetId,
    ).get();
    return rows.fold<Decimal>(
      Decimal.zero,
      (sum, row) => sum + row.readTable(_db.postings).units,
    );
  }

  Future<List<Lot>> _lotsAt({
    required String ownerUserId,
    required DateTime asOf,
    String? accountId,
    String? assetId,
  }) async {
    final rows = await _movementsThrough(
      ownerUserId: ownerUserId,
      accountId: accountId,
      assetId: assetId,
      asOf: asOf,
    );
    return _reduce(rows);
  }

  Future<List<LedgerLotMovement>> _movementsThrough({
    required String ownerUserId,
    required DateTime asOf,
    String? accountId,
    String? assetId,
  }) async {
    _requireIdentity(ownerUserId, accountId: accountId, assetId: assetId);
    if (!asOf.isUtc) {
      throw ArgumentError.value(asOf, 'asOf', 'must be UTC');
    }
    final query =
        _livePostingQuery(
            ownerUserId: ownerUserId,
            accountId: accountId,
            assetId: assetId,
          )
          ..where(_db.journalEntries.date.isSmallerOrEqualValue(asOf))
          ..orderBy([
            OrderingTerm.asc(_db.journalEntries.date),
            OrderingTerm.asc(_db.postings.position),
            OrderingTerm.asc(_db.postings.id),
          ]);
    final rows = await query.get();
    return List<LedgerLotMovement>.unmodifiable([
      for (final row in rows)
        LedgerLotMovement(
          posting: row.readTable(_db.postings),
          date: row.readTable(_db.journalEntries).date.toUtc(),
        ),
    ]);
  }

  JoinedSelectStatement<HasResultSet, dynamic> _livePostingQuery({
    required String ownerUserId,
    String? accountId,
    String? assetId,
  }) {
    final query =
        _db.select(_db.postings).join([
            innerJoin(
              _db.journalEntries,
              _db.journalEntries.id.equalsExp(_db.postings.journalEntryId) &
                  _db.journalEntries.ownerUserId.equalsExp(
                    _db.postings.ownerUserId,
                  ),
            ),
            innerJoin(
              _db.assets,
              _db.assets.id.equalsExp(_db.postings.unit) &
                  _db.assets.ownerUserId.equalsExp(_db.postings.ownerUserId),
            ),
          ])
          ..where(_db.postings.ownerUserId.equals(ownerUserId))
          ..where(_db.journalEntries.ownerUserId.equals(ownerUserId))
          ..where(_db.assets.ownerUserId.equals(ownerUserId))
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.journalEntries.deletedAt.isNull())
          ..where(_db.assets.deletedAt.isNull());
    if (accountId != null) {
      query.where(_db.postings.accountId.equals(accountId));
    }
    if (assetId != null) query.where(_db.postings.unit.equals(assetId));
    return query;
  }

  List<Lot> _reduce(List<LedgerLotMovement> rows) {
    final lots = <Lot>[];
    for (final row in rows) {
      _applyMovement(lots, row);
    }
    return List<Lot>.unmodifiable(lots);
  }

  void _applyMovement(List<Lot> lots, LedgerLotMovement row) {
    final posting = row.posting;
    final cost = posting.costPerUnit;
    final costCurrency = posting.costCurrency;
    if (cost == null || costCurrency == null) return;
    if (posting.units > Decimal.zero) {
      lots.add(
        Lot(
          id: posting.costLotId ?? posting.id,
          openingTransactionId: posting.journalEntryId,
          accountId: posting.accountId,
          assetId: posting.unit,
          currency: costCurrency,
          originalQuantity: posting.units,
          remainingQuantity: posting.units,
          costPerUnit: cost,
          openedAt: posting.costAcquiredOn ?? row.date,
        ),
      );
    } else if (posting.units < Decimal.zero) {
      _reduceLots(
        lots,
        accountId: posting.accountId,
        assetId: posting.unit,
        lotId: posting.costLotId,
        quantity: -posting.units,
      );
    }
  }

  void _reduceLots(
    List<Lot> lots, {
    required String accountId,
    required String assetId,
    required String? lotId,
    required Decimal quantity,
  }) {
    var remaining = quantity;
    final candidates =
        lots
            .where(
              (lot) =>
                  !lot.isClosed &&
                  lot.accountId == accountId &&
                  lot.assetId == assetId &&
                  (lotId == null || lot.id == lotId),
            )
            .toList()
          ..sort((a, b) {
            final byDate = a.openedAt.compareTo(b.openedAt);
            return byDate != 0 ? byDate : a.id.compareTo(b.id);
          });
    for (final lot in candidates) {
      if (remaining <= Decimal.zero) break;
      final closeQuantity = lot.remainingQuantity < remaining
          ? lot.remainingQuantity
          : remaining;
      final index = lots.indexOf(lot);
      lots[index] = lot.copyWith(
        remainingQuantity: lot.remainingQuantity - closeQuantity,
      );
      remaining -= closeQuantity;
    }
  }

  void _requireIdentity(
    String ownerUserId, {
    String? accountId,
    String? assetId,
  }) {
    if (ownerUserId.isEmpty || accountId == '' || assetId == '') {
      throw ArgumentError('Ledger lot identity must not be empty.');
    }
  }
}
