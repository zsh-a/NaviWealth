import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

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
    return snapshotAsync.when(
      loading: () => const SkeletonCard(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 80, height: 14, radius: 4),
            SizedBox(height: 12),
            SkeletonBox(height: 18),
            SizedBox(height: 8),
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
        return FCard.raw(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.assetDetailHoldingsTitle,
                  style: context.theme.typography.sm,
                ),
                const SizedBox(height: 12),
                AssetDetailMetricRow(
                  label: l10n.assetDetailCurrentQuantity,
                  value: hasPosition
                      ? formatAssetDetailQuantity(qty)
                      : '\u2014',
                ),
                const SizedBox(height: 8),
                AssetDetailMetricRow(
                  label: l10n.assetDetailAverageCost,
                  trailing: AnimatedMoneyText(
                    amount: avgCost?.toDouble(),
                    currencyCode: asset.currency,
                    fractionDigits: assetDetailPriceFractionDigits(asset.type),
                  ),
                ),
                const SizedBox(height: 8),
                AssetDetailMetricRow(
                  label: l10n.assetDetailCurrentMarketValue,
                  trailing: OptionalHero(
                    tag: 'asset-${asset.id}-value',
                    child: AnimatedMoneyText(
                      amount: marketValueAsset?.toDouble(),
                      currencyCode: asset.currency,
                      style: context.theme.typography.md,
                    ),
                  ),
                ),
                if (snap != null && snap.marketValueInAssetCurrency.sign == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.assetDetailPriceUnavailable,
                      style: context.theme.typography.xs.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
