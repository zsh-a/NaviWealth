import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/data/dashboard_providers.dart';
import '../../home/domain/dashboard_models.dart';
import '../../home/ui/asset_category_visuals.dart';
import '../domain/wealth_perspective.dart';

/// User's currently selected perspective on the Wealth allocation
/// section. Stored as a [StateProvider] so the segmented control state
/// outlives short widget rebuilds (e.g. when the snapshot stream emits
/// a new value).
final wealthPerspectiveProvider = StateProvider<WealthPerspective>(
  (ref) => WealthPerspective.byCategory,
);

/// Section on the Wealth hub that lets the user flip between
/// "by category" and "by currency" views of the same holdings.
class WealthPerspectiveSection extends ConsumerWidget {
  const WealthPerspectiveSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    final perspective = ref.watch(wealthPerspectiveProvider);
    final snapshot = snapshotAsync.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            l10n.wealthPerspectiveSectionTitle,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
        _PerspectiveToggle(
          value: perspective,
          onChanged: (next) =>
              ref.read(wealthPerspectiveProvider.notifier).state = next,
        ),
        const SizedBox(height: AppSpacing.s12),
        if (snapshot == null)
          const _Skeleton()
        else
          _PerspectiveBody(snapshot: snapshot, perspective: perspective),
      ],
    );
  }
}

class _PerspectiveToggle extends StatelessWidget {
  const _PerspectiveToggle({required this.value, required this.onChanged});

  final WealthPerspective value;
  final ValueChanged<WealthPerspective> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final segments = <(WealthPerspective, String)>[
      (WealthPerspective.byCategory, l10n.wealthPerspectiveByCategory),
      (WealthPerspective.byCurrency, l10n.wealthPerspectiveByCurrency),
    ];
    return Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: FButton(
              variant: segments[i].$1 == value
                  ? FButtonVariant.primary
                  : FButtonVariant.outline,
              onPress: () => onChanged(segments[i].$1),
              child: Text(
                segments[i].$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PerspectiveBody extends ConsumerWidget {
  const _PerspectiveBody({required this.snapshot, required this.perspective});

  final DashboardSnapshot snapshot;
  final WealthPerspective perspective;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final aggregation = buildWealthAggregation(
      snapshot: snapshot,
      perspective: perspective,
      categoryLabel: (c) => AssetCategoryVisuals.label(l10n, c),
    );
    if (aggregation.buckets.isEmpty) {
      return SoftCard(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Text(
          l10n.wealthPerspectiveEmpty,
          style: context.theme.typography.sm.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      );
    }
    final formatters = context.formatters(ref);
    final totalAmount = aggregation.total.amount;
    final base = aggregation.total.currency;
    return SoftCard(
      child: Column(
        children: [
          for (var i = 0; i < aggregation.buckets.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 1,
                  color: context.theme.colors.foreground.withValues(
                    alpha: 0.06,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s12,
              ),
              child: _BucketRow(
                bucket: aggregation.buckets[i],
                totalAmount: totalAmount.toDouble(),
                baseCurrency: base,
                formatters: formatters,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.bucket,
    required this.totalAmount,
    required this.baseCurrency,
    required this.formatters,
  });

  final WealthBucket bucket;
  final double totalAmount;
  final String baseCurrency;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final value = bucket.valueInBase.amount.toDouble();
    final share = totalAmount == 0 ? 0.0 : value / totalAmount;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                bucket.label,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.wealthPerspectiveItemCount(bucket.itemCount),
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatters.currency(
                bucket.valueInBase.amount,
                code: baseCurrency,
              ),
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatters.percent(share, decimalDigits: 1),
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 18, radius: 6),
          SizedBox(height: AppSpacing.s8),
          SkeletonBox(height: 18, radius: 6),
        ],
      ),
    );
  }
}
