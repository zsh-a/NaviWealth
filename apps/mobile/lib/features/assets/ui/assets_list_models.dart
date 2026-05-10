import 'package:decimal/decimal.dart';

import '../../../data/domain/account.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/manual_asset_metadata.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../physical/data/physical_asset.dart';

sealed class AssetListRow {
  const AssetListRow();
}

class ManualTypeHeaderRow extends AssetListRow {
  const ManualTypeHeaderRow(this.type);
  final AssetType type;
}

class SecurityTypeHeaderRow extends AssetListRow {
  const SecurityTypeHeaderRow(this.type);
  final AssetType type;
}

class PhysicalHeaderRow extends AssetListRow {
  const PhysicalHeaderRow();
}

class CashGroupHeaderRow extends AssetListRow {
  const CashGroupHeaderRow(this.accountId, this.account);
  final String accountId;
  final Account? account;
}

class ManualAssetTileRow extends AssetListRow {
  const ManualAssetTileRow(this.asset, this.value);
  final Asset asset;
  final Decimal? value;
}

class SecurityAssetTileRow extends AssetListRow {
  const SecurityAssetTileRow(this.asset, this.snapshot);
  final Asset asset;
  final HoldingSnapshot? snapshot;
}

class PhysicalAssetTileRow extends AssetListRow {
  const PhysicalAssetTileRow(this.asset);
  final PhysicalAsset asset;
}

class GapRow extends AssetListRow {
  const GapRow(this.height);
  final double height;
}

List<AssetListRow> buildAssetRows({
  required List<Asset> manual,
  required List<Asset> securities,
  required List<PhysicalAsset> physical,
  required Map<String, HoldingSnapshot> holdings,
  required Map<String, Decimal> valuationMap,
  required Map<String, Account> accountById,
}) {
  final rows = <AssetListRow>[];

  final manualGrouped = <AssetType, List<Asset>>{};
  for (final a in manual) {
    manualGrouped.putIfAbsent(a.type, () => []).add(a);
  }
  final manualOrder = [
    AssetType.cash,
    AssetType.bankDepositDemand,
    AssetType.bankDepositTerm,
    AssetType.wealthProduct,
  ].where(manualGrouped.containsKey);

  for (final type in manualOrder) {
    rows.add(ManualTypeHeaderRow(type));
    if (type == AssetType.cash) {
      rows.addAll(
        _cashRows(
          manualGrouped[type]!,
          valuationMap: valuationMap,
          accountById: accountById,
        ),
      );
    } else {
      for (final asset in manualGrouped[type]!) {
        rows.add(ManualAssetTileRow(asset, valuationMap[asset.id]));
      }
    }
    rows.add(const GapRow(12));
  }

  final securitiesGrouped = <AssetType, List<Asset>>{};
  for (final a in securities) {
    securitiesGrouped.putIfAbsent(a.type, () => []).add(a);
  }
  final securitiesOrder = kSecuritiesTypeOrder
      .where(securitiesGrouped.containsKey)
      .toList(growable: false);
  for (final type in securitiesOrder) {
    rows.add(SecurityTypeHeaderRow(type));
    for (final asset in securitiesGrouped[type]!) {
      rows.add(SecurityAssetTileRow(asset, holdings[asset.id]));
    }
    rows.add(const GapRow(12));
  }

  if (physical.isNotEmpty) {
    rows.add(const PhysicalHeaderRow());
    for (final asset in physical) {
      rows.add(PhysicalAssetTileRow(asset));
      rows.add(const GapRow(8));
    }
    rows.add(const GapRow(12));
  }

  return rows;
}

List<AssetListRow> _cashRows(
  List<Asset> cashAssets, {
  required Map<String, Decimal> valuationMap,
  required Map<String, Account> accountById,
}) {
  final rows = <AssetListRow>[];
  final byAccount = <String, List<Asset>>{};
  final orphanAssets = <Asset>[];
  for (final asset in cashAssets) {
    final meta = ManualAssetMetadata.decode(asset.metadataJson);
    final accountId = meta?.accountId;
    if (accountId != null) {
      byAccount.putIfAbsent(accountId, () => []).add(asset);
    } else {
      orphanAssets.add(asset);
    }
  }

  final sortedAccountIds = byAccount.keys.toList()
    ..sort((a, b) {
      final aa = accountById[a];
      final bb = accountById[b];
      if (aa == null && bb == null) return 0;
      if (aa == null) return 1;
      if (bb == null) return -1;
      return aa.name.compareTo(bb.name);
    });

  for (final accountId in sortedAccountIds) {
    rows.add(CashGroupHeaderRow(accountId, accountById[accountId]));
    for (final asset in byAccount[accountId]!) {
      rows.add(ManualAssetTileRow(asset, valuationMap[asset.id]));
    }
  }
  for (final asset in orphanAssets) {
    rows.add(ManualAssetTileRow(asset, valuationMap[asset.id]));
  }
  return rows;
}

/// Stable display order for the securities section: type bucket first
/// (stocks -> ETFs -> funds -> bonds -> crypto), then symbol within bucket.
const List<AssetType> kSecuritiesTypeOrder = <AssetType>[
  AssetType.stock,
  AssetType.etf,
  AssetType.mutualFund,
  AssetType.bond,
  AssetType.crypto,
];

List<Asset> orderedSecurities(List<Asset>? assets) {
  if (assets == null || assets.isEmpty) return const <Asset>[];
  final ordered = [...assets];
  ordered.sort((a, b) {
    final ai = kSecuritiesTypeOrder.indexOf(a.type);
    final bi = kSecuritiesTypeOrder.indexOf(b.type);
    final aIdx = ai < 0 ? kSecuritiesTypeOrder.length : ai;
    final bIdx = bi < 0 ? kSecuritiesTypeOrder.length : bi;
    if (aIdx != bIdx) return aIdx.compareTo(bIdx);
    return a.symbol.compareTo(b.symbol);
  });
  return ordered;
}
