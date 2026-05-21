import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/op.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../data/db/app_database.dart';
import '../../../data/domain/hlc.dart';
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
  })  : _db = db,
        _outbox = outbox,
        _stamper = stamper;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  Stream<List<TradeJournalEntry>> watchActive(String ownerUserId) {
    final query = _db.select(_db.optionsTradeJournal)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.openedAt)]);
    return query
        .watch()
        .map((rows) => rows.map(_rowToDomain).toList(growable: false));
  }

  Future<TradeJournalEntry?> get(String id) async {
    final row = await (_db.select(_db.optionsTradeJournal)
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
    final fields = _fields(
      id: id,
      strategy: strategy.wire,
      symbol: symbol,
      optionSymbol: optionSymbol,
      openedAt: openedAt,
      closedAt: null,
      entryCredit: entryCredit,
      exitDebit: null,
      realizedPnl: null,
      currency: currency,
      status: status.wire,
      notes: notes,
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: null,
    );
    await _db.transaction(() async {
      await _db.into(_db.optionsTradeJournal).insertOnConflictUpdate(companion);
      await _enqueue(OpType.insert, id, fields, stamp);
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
    final diff = <String, Object?>{
      'strategy': entry.strategy.wire,
      'symbol': entry.symbol,
      'option_symbol': entry.optionSymbol,
      'opened_at': _iso(entry.openedAt),
      'closed_at': _isoOrNull(entry.closedAt),
      'entry_credit': entry.entryCredit.toString(),
      'exit_debit': entry.exitDebit?.toString(),
      'realized_pnl': entry.realizedPnl?.toString(),
      'currency': entry.currency,
      'status': entry.status.wire,
      'notes': entry.notes,
      'updated_at': _iso(stamp.now),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
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
      await _enqueue(OpType.update, entry.id, diff, stamp);
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
      await _enqueue(OpType.delete, entry.id, null, stamp);
    });
  }

  Future<void> _enqueue(
    OpType type,
    String rowId,
    Map<String, Object?>? fields,
    MutationStamp stamp,
  ) {
    return _outbox.enqueue(
      Op(
        opId: _uuid.v4(),
        tableName: 'options_trade_journal',
        rowId: rowId,
        opType: type,
        fieldsDiff: fields,
        hlc: stamp.hlc,
        deviceId: stamp.deviceId,
      ),
    );
  }
}

TradeJournalEntry _rowToDomain(OptionsTradeJournalRow row) {
  final strategy = parseOptionsStrategyKind(row.strategy) ??
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

Map<String, Object?> _fields({
  required String id,
  required String strategy,
  required String symbol,
  required String optionSymbol,
  required DateTime openedAt,
  required DateTime? closedAt,
  required Decimal entryCredit,
  required Decimal? exitDebit,
  required Decimal? realizedPnl,
  required String currency,
  required String status,
  required String? notes,
  required String ownerUserId,
  required DateTime updatedAt,
  required String updatedByDevice,
  required Hlc hlc,
  required DateTime? deletedAt,
}) =>
    {
      'id': id,
      'strategy': strategy,
      'symbol': symbol,
      'option_symbol': optionSymbol,
      'opened_at': _iso(openedAt),
      'closed_at': _isoOrNull(closedAt),
      'entry_credit': entryCredit.toString(),
      'exit_debit': exitDebit?.toString(),
      'realized_pnl': realizedPnl?.toString(),
      'currency': currency,
      'status': status,
      'notes': notes,
      'owner_user_id': ownerUserId,
      'updated_at': _iso(updatedAt),
      'updated_by_device': updatedByDevice,
      'hlc': hlc.toString(),
      'deleted_at': _isoOrNull(deletedAt),
    };

String _iso(DateTime value) => value.toUtc().toIso8601String();
String? _isoOrNull(DateTime? value) => value == null ? null : _iso(value);
