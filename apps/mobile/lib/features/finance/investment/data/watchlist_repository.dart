import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

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

class WatchlistCollection {
  const WatchlistCollection({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final SyncMeta sync;
}

class WatchlistCollectionMember {
  const WatchlistCollectionMember({
    required this.id,
    required this.collectionId,
    required this.watchlistItemId,
    required this.addedAt,
    required this.sync,
  });

  final String id;
  final String collectionId;
  final String watchlistItemId;
  final DateTime addedAt;
  final SyncMeta sync;
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
  static const String _collectionsTableName = 'watchlist_collections';
  static const String _membersTableName = 'watchlist_collection_members';

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

  Stream<List<WatchlistCollection>> watchCollections(String ownerUserId) {
    final query = _db.select(_db.watchlistCollections)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_collectionRowToDomain).toList(growable: false),
    );
  }

  Stream<List<WatchlistCollectionMember>> watchCollectionMembers(
    String ownerUserId,
  ) {
    final query = _db.select(_db.watchlistCollectionMembers)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.addedAt)]);
    return query.watch().map(
      (rows) => rows.map(_memberRowToDomain).toList(growable: false),
    );
  }

  Future<WatchlistItem> add({
    required String symbol,
    required AssetMarket market,
    PriceAlertRules rules = const PriceAlertRules(),
    Iterable<String> collectionIds = const <String>[],
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
      final requestedCollectionIds = collectionIds.toSet();
      final activeCollectionIds = requestedCollectionIds.isEmpty
          ? const <String>{}
          : (await (_db.select(_db.watchlistCollections)..where(
                      (t) =>
                          t.ownerUserId.equals(stamp.ownerUserId) &
                          t.deletedAt.isNull(),
                    ))
                    .get())
                .map((entry) => entry.id)
                .toSet();
      for (final collectionId in requestedCollectionIds.intersection(
        activeCollectionIds,
      )) {
        await _upsertMembership(
          collectionId: collectionId,
          watchlistItemId: id,
          stamp: stamp,
        );
      }
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

  Future<WatchlistCollection> createCollection(String name) async {
    final normalizedName = _requireCollectionName(name);
    final stamp = await _stamper.stamp();
    final collection = WatchlistCollection(
      id: _uuid.v4(),
      name: normalizedName,
      createdAt: stamp.now,
      sync: _syncFromStamp(stamp),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.watchlistCollections)
          .insert(
            WatchlistCollectionsCompanion.insert(
              id: collection.id,
              name: collection.name,
              createdAt: collection.createdAt,
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
              deletedAt: const Value(null),
            ),
          );
      await _outbox.enqueue(table: _collectionsTableName, rowId: collection.id);
    });
    return collection;
  }

  Future<void> renameCollection({
    required WatchlistCollection collection,
    required String name,
  }) async {
    final normalizedName = _requireCollectionName(name);
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(_db.watchlistCollections)..where(
            (t) =>
                t.id.equals(collection.id) &
                t.ownerUserId.equals(stamp.ownerUserId),
          ))
          .write(
            WatchlistCollectionsCompanion(
              name: Value(normalizedName),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _outbox.enqueue(table: _collectionsTableName, rowId: collection.id);
    });
  }

  Future<void> deleteCollection(WatchlistCollection collection) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final members =
          await (_db.select(_db.watchlistCollectionMembers)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.collectionId.equals(collection.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      await (_db.update(_db.watchlistCollections)..where(
            (t) =>
                t.id.equals(collection.id) &
                t.ownerUserId.equals(stamp.ownerUserId),
          ))
          .write(_collectionTombstone(stamp));
      await _outbox.enqueue(table: _collectionsTableName, rowId: collection.id);
      for (final member in members) {
        await (_db.update(
          _db.watchlistCollectionMembers,
        )..where((t) => t.id.equals(member.id))).write(_memberTombstone(stamp));
        await _outbox.enqueue(table: _membersTableName, rowId: member.id);
      }
    });
  }

  Future<void> setCollectionsForItem({
    required WatchlistItem item,
    required Set<String> collectionIds,
  }) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final activeCollections =
          await (_db.select(_db.watchlistCollections)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.deletedAt.isNull(),
              ))
              .get();
      final activeIds = activeCollections.map((row) => row.id).toSet();
      if (!activeIds.containsAll(collectionIds)) {
        throw StateError('One or more watchlist collections are inactive.');
      }

      final currentRows =
          await (_db.select(_db.watchlistCollectionMembers)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.watchlistItemId.equals(item.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      final currentByCollection = <String, WatchlistCollectionMemberRow>{
        for (final row in currentRows) row.collectionId: row,
      };

      for (final collectionId in collectionIds.difference(
        currentByCollection.keys.toSet(),
      )) {
        await _upsertMembership(
          collectionId: collectionId,
          watchlistItemId: item.id,
          stamp: stamp,
        );
      }
      for (final collectionId in currentByCollection.keys.toSet().difference(
        collectionIds,
      )) {
        final row = currentByCollection[collectionId]!;
        await (_db.update(
          _db.watchlistCollectionMembers,
        )..where((t) => t.id.equals(row.id))).write(_memberTombstone(stamp));
        await _outbox.enqueue(table: _membersTableName, rowId: row.id);
      }
    });
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

  Future<List<String>> remove(WatchlistItem item) async {
    final stamp = await _stamper.stamp();
    final removedCollectionIds = <String>[];
    await _db.transaction(() async {
      final members =
          await (_db.select(_db.watchlistCollectionMembers)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.watchlistItemId.equals(item.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      removedCollectionIds.addAll(members.map((row) => row.collectionId));
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
      for (final member in members) {
        await (_db.update(
          _db.watchlistCollectionMembers,
        )..where((t) => t.id.equals(member.id))).write(_memberTombstone(stamp));
        await _outbox.enqueue(table: _membersTableName, rowId: member.id);
      }
    });
    return List<String>.unmodifiable(removedCollectionIds);
  }

  Future<void> _upsertMembership({
    required String collectionId,
    required String watchlistItemId,
    required MutationStamp stamp,
  }) async {
    final id = membershipIdFor(
      collectionId: collectionId,
      watchlistItemId: watchlistItemId,
    );
    await _db
        .into(_db.watchlistCollectionMembers)
        .insertOnConflictUpdate(
          WatchlistCollectionMembersCompanion.insert(
            id: id,
            collectionId: collectionId,
            watchlistItemId: watchlistItemId,
            addedAt: stamp.now,
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
            deletedAt: const Value(null),
          ),
        );
    await _outbox.enqueue(table: _membersTableName, rowId: id);
  }

  static String idFor({required AssetMarket market, required String symbol}) =>
      '${market.wire}:${symbol.trim().toUpperCase()}';

  static String membershipIdFor({
    required String collectionId,
    required String watchlistItemId,
  }) {
    final digest = sha256.convert(
      utf8.encode('$collectionId\u0000$watchlistItemId'),
    );
    return 'watchlist-member:$digest';
  }
}

String _requireCollectionName(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(name, 'name', 'Collection name cannot be empty');
  }
  return normalized;
}

SyncMeta _syncFromStamp(MutationStamp stamp) => SyncMeta(
  ownerUserId: stamp.ownerUserId,
  updatedAt: stamp.now,
  updatedByDevice: stamp.deviceId,
  hlc: stamp.hlc,
);

WatchlistCollectionsCompanion _collectionTombstone(MutationStamp stamp) =>
    WatchlistCollectionsCompanion(
      deletedAt: Value(stamp.now),
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );

WatchlistCollectionMembersCompanion _memberTombstone(MutationStamp stamp) =>
    WatchlistCollectionMembersCompanion(
      deletedAt: Value(stamp.now),
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );

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

WatchlistCollection _collectionRowToDomain(WatchlistCollectionRow row) =>
    WatchlistCollection(
      id: row.id,
      name: row.name,
      createdAt: row.createdAt,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
      ),
    );

WatchlistCollectionMember _memberRowToDomain(
  WatchlistCollectionMemberRow row,
) => WatchlistCollectionMember(
  id: row.id,
  collectionId: row.collectionId,
  watchlistItemId: row.watchlistItemId,
  addedAt: row.addedAt,
  sync: SyncMeta(
    ownerUserId: row.ownerUserId,
    updatedAt: row.updatedAt,
    updatedByDevice: row.updatedByDevice,
    hlc: row.hlc,
  ),
);
