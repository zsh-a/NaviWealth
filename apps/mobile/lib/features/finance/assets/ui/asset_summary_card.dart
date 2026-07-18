import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/asset_detail_providers.dart';
import 'asset_detail_common.dart';

class AssetSummaryCard extends ConsumerWidget {
  const AssetSummaryCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final historyKey = assetDetailHistoryKey(asset);
    final holding = ref.watch(assetHoldingSnapshotProvider(asset.id)).value;
    final history = historyKey == null
        ? null
        : ref.watch(assetPriceHistoryProvider(historyKey));
    final bars = [...?history?.value?.data]
      ..sort((a, b) => a.asOf.compareTo(b.asOf));
    final latest = bars.isEmpty ? null : bars.last;
    final valuationPrice = holding?.unitPriceInAssetCurrency;
    final displayedPrice = valuationPrice ?? latest?.close;
    final comparisonClose = valuationComparisonClose(
      bars,
      valuationPrice: valuationPrice,
      valuationAsOf: holding?.priceAsOf,
    );
    final changePercent =
        displayedPrice == null ||
            comparisonClose == null ||
            comparisonClose.sign == 0
        ? null
        : ((displayedPrice - comparisonClose) / comparisonClose).toDouble() *
              100;
    return SoftCard.hero(
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  asset.symbol,
                  style: context.displayTitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppBadge(
                label: asset.market ?? l10n.assetDetailUnknown,
                size: AppBadgeSize.compact,
              ),
              const SizedBox(width: AppSpacing.s6),
              AppBadge(label: asset.currency, size: AppBadgeSize.compact),
            ],
          ),
          if (asset.name != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              asset.name!,
              style: context.bodyCaptionStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.s16),
          Text(
            valuationPrice == null
                ? l10n.assetDetailLastClose
                : l10n.assetDetailValuationPrice,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s4),
          if (history?.isLoading == true && latest == null)
            const SkeletonBox(width: 160, height: 30, radius: 6)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedMoneyText(
                    amount: displayedPrice?.toDouble(),
                    currencyCode: holding?.assetCurrency ?? asset.currency,
                    fractionDigits: assetDetailPriceFractionDigits(asset.type),
                    style: TypographyTokens.numericTitleStrong,
                  ),
                ),
                DeltaChip(value: changePercent, fractionDigits: 2),
              ],
            ),
          if (history?.value?.isStale == true) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(l10n.assetDetailQuoteStale, style: context.captionStyle),
          ],
        ],
      ),
    );
  }
}
