import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';

import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/equity_allocation.dart';
import '../domain/equity_classification.dart';

/// Bottom sheet listing the holdings inside a bucket. Tapping a row jumps
/// to the existing asset detail route.
class EquityBucketHoldingsSheet extends ConsumerWidget {
  const EquityBucketHoldingsSheet({
    super.key,
    required this.bucket,
    required this.baseCurrency,
  });

  final EquityAllocationBucket bucket;
  final String baseCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        AppSpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.analyticsBucketSheetTitle(localizeBucketLabel(l10n, bucket)),
            style: context.theme.typography.body.lg,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.analyticsHoldingsCount(bucket.holdings.length),
            style: context.captionStyle,
          ),
          if (bucket.isUnclassified) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(l10n.analyticsUnclassifiedRowCta, style: context.captionStyle),
          ],
          const SizedBox(height: AppSpacing.s12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: bucket.holdings.length,
              separatorBuilder: (_, _) => const FDivider(),
              itemBuilder: (context, index) {
                final h = bucket.holdings[index];
                return FTile(
                  title: Text(h.name ?? h.symbol),
                  subtitle: Text(h.symbol),
                  suffix: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedMoneyText(
                        amount: h.marketValueInBase.toDouble(),
                        currencyCode: baseCurrency,
                        style: context.theme.typography.body.sm,
                        minDeltaThreshold: 0.01,
                      ),
                      Text(
                        formatters.percent(
                          h.weight.toDouble(),
                          decimalDigits: 1,
                        ),
                        style: context.captionStyle,
                      ),
                    ],
                  ),
                  onPress: () {
                    Navigator.of(context).pop();
                    context.goNamed(
                      FinanceRouteNames.wealthAssetDetail,
                      pathParameters: {'assetId': h.assetId},
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String localizeBucketLabel(
  AppLocalizations l10n,
  EquityAllocationBucket bucket,
) {
  if (bucket.isUnclassified) return l10n.analyticsBucketUnclassified;
  switch (bucket.dimension) {
    case EquityAllocationDimension.sector:
      return bucket.label;
    case EquityAllocationDimension.region:
      switch (bucket.label) {
        case 'cnA':
          return l10n.analyticsBucketRegionCnA;
        case 'hkStock':
          return l10n.analyticsBucketRegionHk;
        case 'usStock':
          return l10n.analyticsBucketRegionUs;
        case 'crypto':
          return l10n.analyticsBucketRegionCrypto;
        case 'fx':
          return l10n.analyticsBucketRegionFx;
        default:
          return l10n.analyticsBucketRegionUnknown;
      }
    case EquityAllocationDimension.marketCap:
      switch (bucket.label) {
        case 'large':
          return l10n.analyticsBucketMarketCapLarge;
        case 'mid':
          return l10n.analyticsBucketMarketCapMid;
        case 'small':
          return l10n.analyticsBucketMarketCapSmall;
        default:
          return bucket.label;
      }
  }
}
