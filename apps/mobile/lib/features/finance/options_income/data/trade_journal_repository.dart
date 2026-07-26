import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:uuid/uuid.dart';

import '../domain/options_strategy_profile.dart';
import '../domain/trade_journal_entry.dart';

const _uuid = Uuid();

/// Synced CRUD surface for `options_trade_journal`. Mirrors the
/// approved-underlyings pattern: insert / update / soft-delete with
/// matching OpLog entries.
class TradeJournalRepository {
  TradeJournalRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  static const String _tableName = 'options_trade_journal';

  Stream<List<TradeJournalEntry>> watchActive(String ownerUserId) {
    final query = _db.select(_db.optionsTradeJournal)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.openedAt)]);
    return query.watch().map(
      (rows) => rows.map(_rowToDomain).toList(growable: false),
    );
  }

  Future<TradeJournalEntry?> get(String id) async {
    final row =
        await (_db.select(_db.optionsTradeJournal)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  Future<TradeJournalEntry> create({
    required String underlyingAssetId,
    required OptionsStrategyKind strategy,
    required String symbol,
    required String optionSymbol,
    required DateTime openedAt,
    DateTime? expirationAt,
    required Decimal entryCredit,
    required String currency,
    TradeJournalStatus status = TradeJournalStatus.open,
    DateTime? closedAt,
    Decimal? exitDebit,
    Decimal? fees,
    Decimal? realizedPnl,
    String? notes,
    String? brokerageAccountId,
    String? cashAccountId,
    String? underlyingMarket,
    Decimal? strikePrice,
    int? contractSize,
    int contractQuantity = 1,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final companion = OptionsTradeJournalCompanion.insert(
      id: id,
      underlyingAssetId: underlyingAssetId,
      strategy: strategy.wire,
      symbol: symbol,
      optionSymbol: optionSymbol,
      openedAt: openedAt,
      expirationAt: Value(expirationAt),
      closedAt: Value(closedAt),
      entryCredit: entryCredit,
      exitDebit: Value(exitDebit),
      fees: Value(fees),
      realizedPnl: Value(realizedPnl),
      currency: currency,
      status: status.wire,
      notes: Value(notes),
      brokerageAccountId: Value(brokerageAccountId),
      cashAccountId: Value(cashAccountId),
      underlyingMarket: Value(underlyingMarket),
      strikePrice: Value(strikePrice),
      contractSize: Value(contractSize),
      contractQuantity: Value(contractQuantity),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );
    await _db.transaction(() async {
      await _db.into(_db.optionsTradeJournal).insertOnConflictUpdate(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return TradeJournalEntry(
      id: id,
      underlyingAssetId: underlyingAssetId,
      strategy: strategy,
      symbol: symbol,
      optionSymbol: optionSymbol,
      openedAt: openedAt,
      expirationAt: expirationAt,
      closedAt: closedAt,
      entryCredit: entryCredit,
      exitDebit: exitDebit,
      fees: fees,
      realizedPnl: realizedPnl,
      currency: currency,
      status: status,
      notes: notes,
      brokerageAccountId: brokerageAccountId,
      cashAccountId: cashAccountId,
      underlyingMarket: underlyingMarket,
      strikePrice: strikePrice,
      contractSize: contractSize,
      contractQuantity: contractQuantity,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
  }

  Future<TradeJournalEntry> update(TradeJournalEntry entry) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.optionsTradeJournal,
      )..where((t) => t.id.equals(entry.id))).write(
        OptionsTradeJournalCompanion(
          strategy: Value(entry.strategy.wire),
          underlyingAssetId: Value(entry.underlyingAssetId),
          symbol: Value(entry.symbol),
          optionSymbol: Value(entry.optionSymbol),
          openedAt: Value(entry.openedAt),
          expirationAt: Value(entry.expirationAt),
          closedAt: Value(entry.closedAt),
          entryCredit: Value(entry.entryCredit),
          exitDebit: Value(entry.exitDebit),
          fees: Value(entry.fees),
          realizedPnl: Value(entry.realizedPnl),
          currency: Value(entry.currency),
          status: Value(entry.status.wire),
          notes: Value(entry.notes),
          brokerageAccountId: Value(entry.brokerageAccountId),
          cashAccountId: Value(entry.cashAccountId),
          underlyingMarket: Value(entry.underlyingMarket),
          strikePrice: Value(entry.strikePrice),
          contractSize: Value(entry.contractSize),
          contractQuantity: Value(entry.contractQuantity),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: entry.id);
    });
    return entry.copyWith(
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
  }

  Future<void> remove(TradeJournalEntry entry) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.optionsTradeJournal,
      )..where((t) => t.id.equals(entry.id))).write(
        OptionsTradeJournalCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: entry.id);
    });
  }
}

TradeJournalEntry _rowToDomain(OptionsTradeJournalRow row) {
  final strategy =
      parseOptionsStrategyKind(row.strategy) ??
      OptionsStrategyKind.cashSecuredPut;
  return TradeJournalEntry(
    id: row.id,
    underlyingAssetId: row.underlyingAssetId,
    strategy: strategy,
    symbol: row.symbol,
    optionSymbol: row.optionSymbol,
    openedAt: row.openedAt,
    expirationAt: row.expirationAt,
    closedAt: row.closedAt,
    entryCredit: row.entryCredit,
    exitDebit: row.exitDebit,
    fees: row.fees,
    realizedPnl: row.realizedPnl,
    currency: row.currency,
    status: parseTradeJournalStatus(row.status),
    notes: row.notes,
    brokerageAccountId: row.brokerageAccountId,
    cashAccountId: row.cashAccountId,
    underlyingMarket: row.underlyingMarket,
    strikePrice: row.strikePrice,
    contractSize: row.contractSize,
    contractQuantity: row.contractQuantity,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}
