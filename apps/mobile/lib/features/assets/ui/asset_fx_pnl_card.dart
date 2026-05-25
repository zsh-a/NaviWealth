import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../investment/data/providers.dart';
import 'asset_detail_common.dart';

class AssetFxPnlCard extends ConsumerWidget {
  const AssetFxPnlCard({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reportAsync = ref.watch(assetHoldingReportProvider(assetId));
    if (reportAsync.isLoading) {
      return const SkeletonCard(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 120, height: 14, radius: 4),
            SizedBox(height: 12),
            SkeletonBox(height: 16),
            SizedBox(height: 8),
            SkeletonBox(height: 16),
          ],
        ),
      );
    }
    if (reportAsync.hasError) {
      return AssetDetailErrorCard(
        message: l10n.assetDetailFxPnlLoadError('${reportAsync.error}'),
      );
    }

    final report = reportAsync.value;
    final breakdown = report?.pnlBreakdown;
    final baseCurrency =
        breakdown?.baseCurrency ?? report?.baseCurrency ?? 'USD';
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assetDetailFxPnlTitle,
              style: context.theme.typography.sm,
            ),
            const SizedBox(height: 12),
            AssetDetailMetricRow(
              label: l10n.assetDetailFxPnlMarketLeg,
              trailing: AnimatedMoneyText(
                amount: breakdown?.marketPnLInBase.toDouble(),
                currencyCode: baseCurrency,
                showSign: true,
              ),
            ),
            const SizedBox(height: 8),
            AssetDetailMetricRow(
              label: l10n.assetDetailFxPnlCurrencyLeg,
              trailing: AnimatedMoneyText(
                amount: breakdown?.fxPnLInBase.toDouble(),
                currencyCode: baseCurrency,
                showSign: true,
              ),
            ),
            const FDivider(),
            AssetDetailMetricRow(
              label: l10n.assetDetailFxPnlTotal,
              trailing: AnimatedMoneyText(
                amount: breakdown?.totalPnLInBase.toDouble(),
                currencyCode: baseCurrency,
                showSign: true,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
