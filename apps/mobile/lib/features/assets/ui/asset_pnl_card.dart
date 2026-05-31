import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:naviwealth/features/finance/data/domain/asset.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../asset_detail_providers.dart';
import 'asset_detail_common.dart';

class AssetPnLCard extends ConsumerWidget {
  const AssetPnLCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(assetHoldingSnapshotProvider(asset.id));
    final marketKey = assetDetailHistoryKey(asset);
    final historyAsync = marketKey == null
        ? null
        : ref.watch(assetPriceHistoryProvider(marketKey));

    if (snapshotAsync.isLoading) {
      return const SkeletonCard(
        padding: EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 80, height: 14, radius: 4),
            SizedBox(height: AppSpacing.s12),
            SkeletonBox(height: 22),
            SizedBox(height: AppSpacing.s8),
            SkeletonBox(height: 14),
            SizedBox(height: AppSpacing.s8),
            SkeletonBox(height: 14),
          ],
        ),
      );
    }
    if (snapshotAsync.hasError) {
      return AssetDetailErrorCard(
        message: l10n.assetDetailPnLLoadError('${snapshotAsync.error}'),
      );
    }

    final snap = snapshotAsync.value;
    final hasPosition = (snap?.quantity.sign ?? 0) > 0;
    final unrealizedAsset = snap == null
        ? null
        : snap.marketValueInAssetCurrency - snap.costBasisInAssetCurrency;
    final unrealizedPct =
        (snap == null || snap.costBasisInAssetCurrency.sign <= 0)
        ? null
        : (unrealizedAsset! / snap.costBasisInAssetCurrency)
              .toDecimal(scaleOnInfinitePrecision: 6)
              .toDouble();

    final dailyChange = (snap == null || !hasPosition)
        ? null
        : dailyChangeFromHistory(historyAsync, snap.quantity);

    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.assetDetailPnLTitle, style: context.theme.typography.sm),
            const SizedBox(height: AppSpacing.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.assetDetailUnrealizedPnL,
                        style: context.theme.typography.xs.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      DeltaText(
                        value: unrealizedAsset?.toDouble(),
                        currencyCode: asset.currency,
                        style: context.theme.typography.md,
                      ),
                    ],
                  ),
                ),
                DeltaChip(
                  value: unrealizedPct == null ? null : unrealizedPct * 100,
                  fractionDigits: 2,
                ),
              ],
            ),
            if (snap != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                '${l10n.assetDetailBaseCurrency(snap.baseCurrency)} '
                '${_formatBaseAmount(snap.unrealizedPnlInBase)}',
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ],
            const FDivider(),
            AssetDetailMetricRow(
              label: l10n.assetDetailTodayChange,
              trailing: _DailyChangeView(
                value: dailyChange,
                currency: asset.currency,
                isLoading: historyAsync?.isLoading ?? false,
                isStale: historyAsync?.value?.isStale ?? false,
                hasHistory: marketKey != null,
                hasPosition: hasPosition,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBaseAmount(Decimal amount) {
    final sign = amount.sign;
    final fmt = NumberFormat.decimalPatternDigits(decimalDigits: 2);
    final formatted = fmt.format(amount.abs().toDouble());
    if (sign < 0) return '-$formatted';
    if (sign > 0) return '+$formatted';
    return formatted;
  }
}

class _DailyChangeView extends StatelessWidget {
  const _DailyChangeView({
    required this.value,
    required this.currency,
    required this.isLoading,
    required this.isStale,
    required this.hasHistory,
    required this.hasPosition,
  });

  final Decimal? value;
  final String currency;
  final bool isLoading;
  final bool isStale;
  final bool hasHistory;
  final bool hasPosition;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!hasPosition || !hasHistory) {
      return Text('\u2014', style: context.theme.typography.sm);
    }
    if (isLoading && value == null) {
      return const SizedBox(
        width: 80,
        child: SkeletonBox(height: 14, radius: 4),
      );
    }
    if (value == null) {
      return Text(
        isStale ? l10n.assetDetailQuoteStale : l10n.assetDetailQuoteUnavailable,
        style: context.theme.typography.xs.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      );
    }
    return DeltaText(value: value!.toDouble(), currencyCode: currency);
  }
}
