import 'package:flutter/widgets.dart';
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
          padding: const EdgeInsets.only(
            left: AppSpacing.s4,
            bottom: AppSpacing.s8,
          ),
          child: Text(
            l10n.wealthPerspectiveSectionTitle,
            style: context.mutedLabelStyle,
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
    return SegmentedRow<WealthPerspective>(
      options: const [
        WealthPerspective.byCategory,
        WealthPerspective.byCurrency,
      ],
      value: value,
      labelOf: (p) => switch (p) {
        WealthPerspective.byCategory => l10n.wealthPerspectiveByCategory,
        WealthPerspective.byCurrency => l10n.wealthPerspectiveByCurrency,
      },
      onChanged: onChanged,
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
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final background = isDark
        ? colors.card.withValues(alpha: AppOpacity.muted)
        : ColorPalette.neutral75;
    final aggregation = buildWealthAggregation(
      snapshot: snapshot,
      perspective: perspective,
      categoryLabel: (c) => AssetCategoryVisuals.label(l10n, c),
    );
    if (aggregation.buckets.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.xlg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Text(
            l10n.wealthPerspectiveEmpty,
            style: context.bodyCaptionStyle,
          ),
        ),
      );
    }
    final formatters = context.formatters(ref);
    final totalAmount = aggregation.total.amount;
    final base = aggregation.total.currency;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xlg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
        child: Column(
          children: [
            for (var i = 0; i < aggregation.buckets.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                child: _BucketRow(
                  bucket: aggregation.buckets[i],
                  totalAmount: totalAmount.toDouble(),
                  baseCurrency: base,
                  formatters: formatters,
                ),
              ),
              if (i != aggregation.buckets.length - 1)
                SizedBox(
                  height: AppSpacing.hairline,
                  child: ColoredBox(
                    color: colors.border.withValues(alpha: AppOpacity.faint),
                  ),
                ),
            ],
          ],
        ),
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
    final colors = context.theme.colors;
    final value = bucket.valueInBase.amount.toDouble();
    final share = totalAmount == 0 ? 0.0 : value / totalAmount;
    final clampedShare = share.clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                bucket.label,
                style: context.labelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatters.currency(
                    bucket.valueInBase.amount,
                    code: baseCurrency,
                  ),
                  style: context.strongLabelStyle,
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  formatters.percent(share, decimalDigits: 1),
                  style: context.captionStyle,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s10),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            height: AppSpacing.s4,
            child: Stack(
              children: [
                ColoredBox(
                  color: colors.foreground.withValues(
                    alpha: AppOpacity.whisper,
                  ),
                  child: const SizedBox.expand(),
                ),
                FractionallySizedBox(
                  widthFactor: clampedShare,
                  alignment: AlignmentDirectional.centerStart,
                  child: ColoredBox(
                    color: colors.primary.withValues(
                      alpha: AppOpacity.disabled,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
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
