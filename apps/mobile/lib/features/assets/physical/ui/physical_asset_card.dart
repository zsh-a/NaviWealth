import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';

import '../../../../app/route_paths.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/physical_asset.dart';

class PhysicalAssetCard extends StatelessWidget {
  const PhysicalAssetCard({super.key, required this.asset});

  final PhysicalAsset asset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      onPress: () => context.goNamed(
        AppRouteNames.wealthPhysicalDetail,
        pathParameters: {'id': asset.id},
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Row(
          children: [
            Icon(_iconForType(asset.type), color: context.theme.colors.primary),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name,
                    style: context.theme.typography.md,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    _subtitleFor(asset, l10n),
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            MoneyText(
              amount: asset.currentValuation.toDouble(),
              currencyCode: asset.currency,
              style: context.theme.typography.md,
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForType(AssetType type) {
    switch (type) {
      case AssetType.realEstate:
        return FLucideIcons.house;
      case AssetType.vehicle:
        return FLucideIcons.car;
      // ignore: no_default_cases
      default:
        return FLucideIcons.package;
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
