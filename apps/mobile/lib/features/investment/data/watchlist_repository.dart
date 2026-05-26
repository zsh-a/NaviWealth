import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/mutation_context.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../domain/values/asset_market.dart';

class PriceAlertRules {
  const PriceAlertRules({this.above, this.below, this.enabled = true});

  final Decimal? above;
  final Decimal? below;
  final bool enabled;

  bool get hasRule => above != null || below != null;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    if (above != null) 'above': above.toString(),
    if (below != null) 'below': below.toString(),
  };

  static PriceAlertRules fromJson(String raw) {
    if (raw.trim().isEmpty) return const PriceAlertRules();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const PriceAlertRules();
    return PriceAlertRules(
      enabled: decoded['enabled'] != false,
      above: _decimalOrNull(decoded['above']),
      below: _decimalOrNull(decoded['below']),
    );
  }

  static Decimal? _decimalOrNull(Object? value) {
    if (value == null) return null;
    return Decimal.tryParse(value.toString());
  }
}

class WatchlistItem {
  const WatchlistItem({
    required this.id,
    required this.symbol,
    required this.market,
    required this.addedAt,
    required this.alertRules,
    required this.sync,
  });

  final String id;
  final String symbol;
  final AssetMarket market;
  final DateTime addedAt;
  final PriceAlertRules alertRules;
  final SyncMeta sync;

  String get displaySymbol => symbol.toUpperCase();
}

class WatchlistRepository {
  WatchlistRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  static const String _tableName = 'watchlist_items';

  Stream<List<WatchlistItem>> watchActive(String ownerUserId) {
    final query = _db.select(_db.watchlistItems)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.addedAt)]);
    return query.watch().map(
      (rows) => rows.map(_rowToDomain).toList(growable: false),
    );
  }

  Future<List<WatchlistItem>> listActive(String ownerUserId) async {
    final query = _db.select(_db.watchlistItems)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.addedAt)]);
    final rows = await query.get();
    return rows.map(_rowToDomain).toList(growable: false);
  }

  Future<WatchlistItem> add({
    required String symbol,
    required AssetMarket market,
    PriceAlertRules rules = const PriceAlertRules(),
  }) async {
    final stamp = await _stamper.stamp();
    final normalizedSymbol = symbol.trim().toUpperCase();
    final id = idFor(market: market, symbol: normalizedSymbol);
    final alertJson = jsonEncode(rules.toJson());
    final row = WatchlistItemsCompanion.insert(
      id: id,
      symbol: normalizedSymbol,
      market: market.wire,
      addedAt: stamp.now,
      alertRulesJson: Value(alertJson),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );
    await _db.transaction(() async {
      await _db.into(_db.watchlistItems).insertOnConflictUpdate(row);
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return WatchlistItem(
      id: id,
      symbol: normalizedSymbol,
      market: market,
      addedAt: stamp.now,
      alertRules: rules,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
  }

  Future<void> updateAlertRules({
    required WatchlistItem item,
    required PriceAlertRules rules,
  }) async {
    final stamp = await _stamper.stamp();
    final alertJson = jsonEncode(rules.toJson());
    await _db.transaction(() async {
      await (_db.update(
        _db.watchlistItems,
      )..where((t) => t.id.equals(item.id))).write(
        WatchlistItemsCompanion(
          alertRulesJson: Value(alertJson),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: item.id);
    });
  }

  Future<void> remove(WatchlistItem item) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.watchlistItems,
      )..where((t) => t.id.equals(item.id))).write(
        WatchlistItemsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: item.id);
    });
  }

  static String idFor({required AssetMarket market, required String symbol}) =>
      '${market.wire}:${symbol.trim().toUpperCase()}';
}

WatchlistItem _rowToDomain(WatchlistItemRow row) {
  final market = assetMarketFromWire(row.market) ?? AssetMarket.unknown;
  return WatchlistItem(
    id: row.id,
    symbol: row.symbol,
    market: market,
    addedAt: row.addedAt,
    alertRules: PriceAlertRules.fromJson(row.alertRulesJson),
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}
