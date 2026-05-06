import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/domain/asset.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../asset_detail_providers.dart';
import 'asset_detail_common.dart';

class AssetHoldingCard extends ConsumerWidget {
  const AssetHoldingCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(assetHoldingSnapshotProvider(asset.id));
    final theme = Theme.of(context);
    return snapshotAsync.when(
      loading: () => const SkeletonCard(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 80, height: 14, radius: Radii.xs),
            SizedBox(height: Spacing.s12),
            SkeletonBox(height: 18),
            SizedBox(height: Spacing.s8),
            SkeletonBox(height: 18),
          ],
        ),
      ),
      error: (e, _) => AssetDetailErrorCard(
        message: l10n.assetDetailHoldingsLoadError('$e'),
      ),
      data: (snap) {
        final qty = snap?.quantity ?? Decimal.zero;
        final hasPosition = qty.sign > 0;
        final avgCost = hasPosition
            ? (snap!.costBasisInAssetCurrency / qty).toDecimal(
                scaleOnInfinitePrecision: 8,
              )
            : null;
        final marketValueAsset = snap?.marketValueInAssetCurrency;
        return LiquidGlassCard(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.assetDetailHoldingsTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: Spacing.s12),
              AssetDetailMetricRow(
                label: l10n.assetDetailCurrentQuantity,
                value: hasPosition ? formatAssetDetailQuantity(qty) : '\u2014',
              ),
              const SizedBox(height: Spacing.s8),
              AssetDetailMetricRow(
                label: l10n.assetDetailAverageCost,
                trailing: AnimatedMoneyText(
                  amount: avgCost?.toDouble(),
                  currencyCode: asset.currency,
                  fractionDigits: assetDetailPriceFractionDigits(asset.type),
                ),
              ),
              const SizedBox(height: Spacing.s8),
              AssetDetailMetricRow(
                label: l10n.assetDetailCurrentMarketValue,
                trailing: OptionalHero(
                  tag: 'asset-${asset.id}-value',
                  child: AnimatedMoneyText(
                    amount: marketValueAsset?.toDouble(),
                    currencyCode: asset.currency,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              if (snap != null && snap.marketValueInAssetCurrency.sign == 0)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.s8),
                  child: Text(
                    l10n.assetDetailPriceUnavailable,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
