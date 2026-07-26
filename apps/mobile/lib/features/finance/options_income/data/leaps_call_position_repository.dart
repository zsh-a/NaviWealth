import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:uuid/uuid.dart';

import '../domain/leaps_call_position.dart';

const _uuid = Uuid();

class LeapsCallPositionRepository {
  LeapsCallPositionRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  static const tableName = 'options_leaps_call_positions';
  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  Stream<List<LeapsCallPosition>> watchActive(String ownerUserId) {
    final query = _db.select(_db.optionsLeapsCallPositions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.openedAt)]);
    return query.watch().map(
      (rows) => rows.map(_rowToDomain).toList(growable: false),
    );
  }

  Future<LeapsCallPosition?> get(String id) async {
    final row =
        await (_db.select(_db.optionsLeapsCallPositions)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  Future<LeapsCallPosition> create({
    required String symbol,
    required String optionSymbol,
    required DateTime openedAt,
    required DateTime expirationAt,
    required Decimal strikePrice,
    required Decimal entryDebit,
    Decimal? exitCredit,
    Decimal? fees,
    String currency = 'USD',
    int contractSize = 100,
    int contractQuantity = 1,
    LeapsCallStatus status = LeapsCallStatus.open,
    DateTime? closedAt,
    Decimal? currentMark,
    Decimal? currentDelta,
    DateTime? markedAt,
    String? brokerageAccountId,
    String? notes,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final position = LeapsCallPosition(
      id: id,
      symbol: symbol.trim().toUpperCase(),
      optionSymbol: optionSymbol.trim(),
      openedAt: openedAt.toUtc(),
      expirationAt: expirationAt.toUtc(),
      closedAt: closedAt?.toUtc(),
      strikePrice: strikePrice,
      entryDebit: entryDebit,
      exitCredit: exitCredit,
      fees: fees ?? Decimal.zero,
      currency: currency.trim().toUpperCase(),
      contractSize: contractSize,
      contractQuantity: contractQuantity,
      status: status,
      currentMark: currentMark,
      currentDelta: currentDelta,
      markedAt: markedAt?.toUtc(),
      brokerageAccountId: brokerageAccountId,
      notes: notes,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.optionsLeapsCallPositions)
          .insertOnConflictUpdate(_toCompanion(position));
      await _outbox.enqueue(table: tableName, rowId: id);
    });
    return position;
  }

  Future<LeapsCallPosition> update(LeapsCallPosition position) async {
    final stamp = await _stamper.stamp();
    final saved = position.copyWith(
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.optionsLeapsCallPositions)
          .insertOnConflictUpdate(_toCompanion(saved));
      await _outbox.enqueue(table: tableName, rowId: saved.id);
    });
    return saved;
  }

  Future<void> remove(LeapsCallPosition position) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.optionsLeapsCallPositions,
      )..where((t) => t.id.equals(position.id))).write(
        OptionsLeapsCallPositionsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: tableName, rowId: position.id);
    });
  }

  OptionsLeapsCallPositionsCompanion _toCompanion(LeapsCallPosition position) =>
      OptionsLeapsCallPositionsCompanion.insert(
        id: position.id,
        symbol: position.symbol,
        optionSymbol: position.optionSymbol,
        openedAt: position.openedAt,
        expirationAt: position.expirationAt,
        closedAt: Value(position.closedAt),
        strikePrice: position.strikePrice,
        entryDebit: position.entryDebit,
        exitCredit: Value(position.exitCredit),
        fees: Value(position.fees),
        currency: position.currency,
        contractSize: Value(position.contractSize),
        contractQuantity: Value(position.contractQuantity),
        status: position.status.wire,
        currentMark: Value(position.currentMark),
        currentDelta: Value(position.currentDelta),
        markedAt: Value(position.markedAt),
        brokerageAccountId: Value(position.brokerageAccountId),
        notes: Value(position.notes),
        ownerUserId: position.sync.ownerUserId,
        updatedAt: position.sync.updatedAt,
        updatedByDevice: position.sync.updatedByDevice,
        hlc: position.sync.hlc,
        deletedAt: const Value(null),
      );
}

LeapsCallPosition _rowToDomain(OptionsLeapsCallPositionRow row) =>
    LeapsCallPosition(
      id: row.id,
      symbol: row.symbol,
      optionSymbol: row.optionSymbol,
      openedAt: row.openedAt,
      expirationAt: row.expirationAt,
      closedAt: row.closedAt,
      strikePrice: row.strikePrice,
      entryDebit: row.entryDebit,
      exitCredit: row.exitCredit,
      fees: row.fees,
      currency: row.currency,
      contractSize: row.contractSize,
      contractQuantity: row.contractQuantity,
      status: parseLeapsCallStatus(row.status),
      currentMark: row.currentMark,
      currentDelta: row.currentDelta,
      markedAt: row.markedAt,
      brokerageAccountId: row.brokerageAccountId,
      notes: row.notes,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
      ),
    );
