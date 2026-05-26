import 'package:drift/drift.dart' hide Column;

import '../../../core/persistence/app_database.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/sync_meta.dart';
import '../domain/equity_allocation.dart';

/// Read-only accessor for equity-class assets (`stock` / `etf` / `mutualFund`).
///
/// The existing repositories live in two narrower silos:
/// - [ManualAssetRepository] only watches the no-market-data flavours
///   (cash, deposit, wealth product).
/// - [PhysicalAssetRepository] only watches real estate / vehicles.
///
/// Equity tracking does not yet have its own write repository (no securities
/// entry form has shipped), so this class exists purely to give the analytics
/// layer a stable read API over the same `assets` table.
class EquityAssetsRepository {
  EquityAssetsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Asset>> watchAll() {
    final query = _db.select(_db.assets)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.type.isInValues(kEquityAssetTypes.toList()),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.symbol)]);
    return query.watch().map((rows) => rows.map(_toAsset).toList());
  }

  Asset _toAsset(AssetRow row) {
    return Asset(
      id: row.id,
      type: row.type,
      symbol: row.symbol,
      currency: row.currency,
      name: row.name,
      market: row.market,
      industry: row.industry,
      region: row.region,
      isin: row.isin,
      logoUrl: row.logoUrl,
      metadataJson: row.metadataJson,
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
