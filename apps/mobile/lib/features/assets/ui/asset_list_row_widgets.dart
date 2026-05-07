import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../physical/ui/physical_asset_card.dart';
import 'asset_row_headers.dart';
import 'asset_type_labels.dart';
import 'assets_list_models.dart';
import 'manual_asset_tile.dart';
import 'security_asset_tile.dart';

class AssetListRowWidget extends StatelessWidget {
  const AssetListRowWidget({
    super.key,
    required this.row,
    required this.selectedAssetId,
    required this.inMasterDetail,
  });

  final AssetListRow row;
  final String? selectedAssetId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (row) {
      ManualTypeHeaderRow(:final type) => AssetSectionHeader(
        title: manualAssetTypeLabel(l10n, type),
      ),
      SecurityTypeHeaderRow(:final type) => AssetSectionHeader(
        title: securitiesAssetTypeLabel(l10n, type),
      ),
      PhysicalHeaderRow() => AssetSectionHeader(
        title: l10n.physicalAssetsSectionTitle,
      ),
      CashGroupHeaderRow(:final accountId, :final account) =>
        CashAccountGroupHeader(accountId: accountId, account: account),
      ManualAssetTileRow(:final asset, :final value) => TertiaryRowSurface(
        child: ManualAssetTile(
          asset: asset,
          selected: asset.id == selectedAssetId,
          heroEnabled: !inMasterDetail,
          value: value,
        ),
      ),
      SecurityAssetTileRow(:final asset, :final snapshot) => TertiaryRowSurface(
        child: SecurityAssetTile(
          asset: asset,
          snapshot: snapshot,
          selected: asset.id == selectedAssetId,
          heroEnabled: !inMasterDetail,
        ),
      ),
      PhysicalAssetTileRow(:final asset) => PhysicalAssetCard(asset: asset),
      GapRow(:final height) => SizedBox(height: height),
    };
  }
}
