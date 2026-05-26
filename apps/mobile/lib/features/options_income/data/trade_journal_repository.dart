import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/repositories/mutation_context.dart';
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
    required OptionsStrategyKind strategy,
    required String symbol,
    required String optionSymbol,
    required DateTime openedAt,
    required Decimal entryCredit,
    required String currency,
    TradeJournalStatus status = TradeJournalStatus.open,
    String? notes,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final companion = OptionsTradeJournalCompanion.insert(
      id: id,
      strategy: strategy.wire,
      symbol: symbol,
      optionSymbol: optionSymbol,
      openedAt: openedAt,
      closedAt: const Value(null),
      entryCredit: entryCredit,
      exitDebit: const Value(null),
      realizedPnl: const Value(null),
      currency: currency,
      status: status.wire,
      notes: Value(notes),
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
      strategy: strategy,
      symbol: symbol,
      optionSymbol: optionSymbol,
      openedAt: openedAt,
      closedAt: null,
      entryCredit: entryCredit,
      exitDebit: null,
      realizedPnl: null,
      currency: currency,
      status: status,
      notes: notes,
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
          symbol: Value(entry.symbol),
          optionSymbol: Value(entry.optionSymbol),
          openedAt: Value(entry.openedAt),
          closedAt: Value(entry.closedAt),
          entryCredit: Value(entry.entryCredit),
          exitDebit: Value(entry.exitDebit),
          realizedPnl: Value(entry.realizedPnl),
          currency: Value(entry.currency),
          status: Value(entry.status.wire),
          notes: Value(entry.notes),
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
    strategy: strategy,
    symbol: row.symbol,
    optionSymbol: row.optionSymbol,
    openedAt: row.openedAt,
    closedAt: row.closedAt,
    entryCredit: row.entryCredit,
    exitDebit: row.exitDebit,
    realizedPnl: row.realizedPnl,
    currency: row.currency,
    status: parseTradeJournalStatus(row.status),
    notes: row.notes,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}
