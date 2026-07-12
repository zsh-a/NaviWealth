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
    final history = historyKey == null
        ? null
        : ref.watch(assetPriceHistoryProvider(historyKey));
    final bars = [...?history?.value?.data]
      ..sort((a, b) => a.asOf.compareTo(b.asOf));
    final latest = bars.isEmpty ? null : bars.last;
    final previous = bars.length < 2 ? null : bars[bars.length - 2];
    final changePercent =
        latest == null || previous == null || previous.close.sign == 0
        ? null
        : ((latest.close - previous.close) / previous.close).toDouble() * 100;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(asset.symbol, style: context.displayTitleStyle),
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
              Text(asset.name!, style: context.bodyCaptionStyle),
            ],
            const SizedBox(height: AppSpacing.s16),
            Text(l10n.assetDetailLastClose, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s4),
            if (history?.isLoading == true && latest == null)
              const SkeletonBox(width: 160, height: 30, radius: 6)
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AnimatedMoneyText(
                      amount: latest?.close.toDouble(),
                      currencyCode: asset.currency,
                      fractionDigits: assetDetailPriceFractionDigits(
                        asset.type,
                      ),
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
      ),
    );
  }
}
