import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/format/providers.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import 'wealth_perspective.dart';

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
    final canChangePerspective =
        snapshot != null &&
        buildWealthAggregation(
              snapshot: snapshot,
              perspective: WealthPerspective.byCurrency,
            ).buckets.length >
            1;
    final effectivePerspective = canChangePerspective
        ? perspective
        : WealthPerspective.byCategory;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.lg,
      level: SoftCardLevel.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (!canChangePerspective) {
                return Text(
                  l10n.wealthPerspectiveSectionTitle,
                  style: context.labelStyle,
                );
              }
              final toggle = _PerspectiveToggle(
                value: effectivePerspective,
                onChanged: (next) =>
                    ref.read(wealthPerspectiveProvider.notifier).state = next,
              );
              if (constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.wealthPerspectiveSectionTitle,
                      style: context.labelStyle,
                    ),
                    const SizedBox(height: AppSpacing.s10),
                    toggle,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.wealthPerspectiveSectionTitle,
                      style: context.labelStyle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: toggle,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.s16),
          if (snapshot == null)
            const _Skeleton()
          else
            _PerspectiveBody(
              snapshot: snapshot,
              perspective: effectivePerspective,
            ),
        ],
      ),
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
    final palette = ChartPalette.of(context);
    final aggregation = buildWealthAggregation(
      snapshot: snapshot,
      perspective: perspective,
      categoryLabel: (c) => AssetCategoryVisuals.label(l10n, c),
    );
    if (aggregation.buckets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Text(
          l10n.wealthPerspectiveEmpty,
          style: context.bodyCaptionStyle,
        ),
      );
    }
    final formatters = context.formatters(ref);
    final totalAmount = aggregation.total.amount;
    final base = aggregation.total.currency;
    final hasComposition = aggregation.buckets.length > 1;
    return Column(
      children: [
        if (hasComposition) ...[
          _AllocationCompositionBar(
            buckets: aggregation.buckets,
            totalAmount: totalAmount.toDouble(),
            palette: palette,
          ),
          const SizedBox(height: AppSpacing.s10),
        ],
        for (var i = 0; i < aggregation.buckets.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
            child: _BucketRow(
              bucket: aggregation.buckets[i],
              accent: palette.accentAt(i),
              totalAmount: totalAmount.toDouble(),
              baseCurrency: base,
              formatters: formatters,
              showShare: hasComposition,
              itemCountLabel: l10n.wealthPerspectiveItemCount(
                aggregation.buckets[i].itemCount,
              ),
              onPressed: () => _showBucketDetail(
                context: context,
                bucket: aggregation.buckets[i],
                baseCurrency: base,
              ),
            ),
          ),
          if (i != aggregation.buckets.length - 1)
            const AppGroupedDivider(indent: AppSpacing.s20),
        ],
      ],
    );
  }

  Future<void> _showBucketDetail({
    required BuildContext context,
    required WealthBucket bucket,
    required String baseCurrency,
  }) {
    final l10n = AppLocalizations.of(context);
    return showAppSheet<void>(
      context: context,
      title: bucket.label,
      subtitle: l10n.wealthPerspectiveItemCount(bucket.itemCount),
      maxHeightFactor: 0.9,
      builder: (sheetContext) => _WealthBucketDetail(
        bucket: bucket,
        baseCurrency: baseCurrency,
        onItemPressed: (item) {
          final route = item.routeHint;
          if (route == null) return;
          Navigator.of(sheetContext).pop();
          if (context.mounted) context.push(route);
        },
      ),
    );
  }
}

class _AllocationCompositionBar extends StatelessWidget {
  const _AllocationCompositionBar({
    required this.buckets,
    required this.totalAmount,
    required this.palette,
  });

  final List<WealthBucket> buckets;
  final double totalAmount;
  final ChartPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      container: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: SizedBox(
          key: const ValueKey('allocation-composition-bar'),
          height: AppSpacing.s10,
          child: ColoredBox(
            color: colors.foreground.withValues(alpha: AppOpacity.whisper),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < buckets.length; i++) ...[
                  Expanded(
                    flex: _segmentFlex(buckets[i]),
                    child: ColoredBox(
                      key: ValueKey(
                        'allocation-composition-segment-${buckets[i].key}',
                      ),
                      color: palette
                          .accentAt(i)
                          .withValues(alpha: AppOpacity.emphasis),
                    ),
                  ),
                  if (i != buckets.length - 1)
                    const SizedBox(width: AppSpacing.s2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _segmentFlex(WealthBucket bucket) {
    if (totalAmount <= 0) return 1;
    final share = bucket.valueInBase.amount.toDouble() / totalAmount;
    return (share * 10000).round().clamp(1, 10000);
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.bucket,
    required this.accent,
    required this.totalAmount,
    required this.baseCurrency,
    required this.formatters,
    required this.showShare,
    required this.itemCountLabel,
    required this.onPressed,
  });

  final WealthBucket bucket;
  final Color accent;
  final double totalAmount;
  final String baseCurrency;
  final AppFormatters formatters;
  final bool showShare;
  final String itemCountLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final value = bucket.valueInBase.amount.toDouble();
    final share = totalAmount == 0 ? 0.0 : value / totalAmount;
    final formattedAmount = formatters.currency(
      bucket.valueInBase.amount,
      code: baseCurrency,
    );
    final formattedShare = formatters.percent(share, decimalDigits: 1);
    return Semantics(
      button: true,
      container: true,
      label: [
        bucket.label,
        itemCountLabel,
        formattedAmount,
        if (showShare) formattedShare,
      ].join(', '),
      child: ExcludeSemantics(
        child: FTappable(
          onPress: onPressed,
          child: Row(
            key: ValueKey('allocation-bucket-${bucket.key}'),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: AppOpacity.emphasis),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: AppSpacing.s10),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: bucket.label, style: context.labelStyle),
                      TextSpan(
                        text: ' · $itemCountLabel',
                        style: context.captionStyle,
                      ),
                    ],
                  ),
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
                    formattedAmount,
                    style: context.strongLabelStyle,
                    maxLines: 1,
                  ),
                  if (showShare) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(formattedShare, style: context.captionStyle),
                  ],
                ],
              ),
              const SizedBox(width: AppSpacing.s6),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.h18,
                color: context.theme.colors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WealthBucketDetail extends StatelessWidget {
  const _WealthBucketDetail({
    required this.bucket,
    required this.baseCurrency,
    required this.onItemPressed,
  });

  final WealthBucket bucket;
  final String baseCurrency;
  final ValueChanged<CategoryItem> onItemPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('wealth-perspective-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    bucket.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.strongTitleStyle,
                  ),
                ),
                MoneyText(
                  amount: bucket.valueInBase.amount.toDouble(),
                  currencyCode: baseCurrency,
                  style: context.strongTitleStyle,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < bucket.items.length; i++) ...[
                _WealthBucketItemRow(
                  item: bucket.items[i],
                  baseCurrency: baseCurrency,
                  onPressed: bucket.items[i].routeHint == null
                      ? null
                      : () => onItemPressed(bucket.items[i]),
                ),
                if (i != bucket.items.length - 1)
                  const AppGroupedDivider(
                    indent: AppSpacing.s12,
                    endIndent: AppSpacing.s12,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WealthBucketItemRow extends StatelessWidget {
  const _WealthBucketItemRow({
    required this.item,
    required this.baseCurrency,
    required this.onPressed,
  });

  final CategoryItem item;
  final String baseCurrency;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final showNative =
        item.nativeCurrency.toUpperCase() != baseCurrency.toUpperCase();
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.labelStyle,
                ),
                if (item.subtitle?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    item.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.captionStyle,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(
                amount: item.valueInBase.amount.toDouble(),
                currencyCode: baseCurrency,
                style: context.labelStyle,
              ),
              if (showNative) ...[
                const SizedBox(height: AppSpacing.s2),
                MoneyText(
                  amount: item.nativeAmount.toDouble(),
                  currencyCode: item.nativeCurrency,
                  symbolStyle: MoneySymbolStyle.isoCode,
                  style: context.captionStyle,
                ),
              ],
            ],
          ),
          if (onPressed != null) ...[
            const SizedBox(width: AppSpacing.s6),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.h18,
              color: context.theme.colors.mutedForeground,
            ),
          ],
        ],
      ),
    );
    if (onPressed == null) return content;
    return Semantics(
      button: true,
      child: FTappable(onPress: onPressed, child: content),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(height: 18, radius: 6),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(height: 18, radius: 6),
      ],
    );
  }
}
