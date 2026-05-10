import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/route_paths.dart';
import '../../../../data/domain/enums.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/physical_asset.dart';

class PhysicalAssetCard extends StatelessWidget {
  const PhysicalAssetCard({super.key, required this.asset});

  final PhysicalAsset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return FCard.raw(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.goNamed(
            AppRouteNames.physicalAssetDetail,
            pathParameters: {'id': asset.id},
          ),
          child: Padding(
            padding: Spacing.card,
            child: Row(
              children: [
                Icon(
                  _iconForType(asset.type),
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: Spacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Spacing.s2),
                      Text(
                        _subtitleFor(asset, l10n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.s12),
                MoneyText(
                  amount: asset.currentValuation.toDouble(),
                  currencyCode: asset.currency,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconForType(AssetType type) {
    switch (type) {
      case AssetType.realEstate:
        return Icons.home_outlined;
      case AssetType.vehicle:
        return Icons.directions_car_outlined;
      // ignore: no_default_cases
      default:
        return Icons.inventory_2_outlined;
    }
  }

  static String _subtitleFor(PhysicalAsset asset, AppLocalizations l10n) {
    if (asset.isRealEstate && (asset.address?.isNotEmpty ?? false)) {
      return asset.address!;
    }
    return asset.isRealEstate
        ? l10n.physicalAssetTypeRealEstate
        : l10n.physicalAssetTypeVehicle;
  }
}
