import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../domain/dashboard_models.dart';
import 'allocation_detail_panel.dart';
import 'asset_category_visuals.dart';
import 'home_section.dart';

/// Compact allocation surface for the home cockpit.
///
/// Replaces the heavy Sankey AllocationCard above the fold with:
///   - a single-row stacked bar (one segment per category, sorted desc)
///   - the top 3 categories as labelled rows below
///   - a footer link into the full Accounts hub for the breakdown
///
/// The full Sankey / drill-down lives on a dedicated detail page; the
/// home only needs the at-a-glance summary.
class AllocationSummary extends StatelessWidget {
  const AllocationSummary({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final assetAllocations =
        snapshot.allocations.where((a) => !a.isLiability).toList()..sort(
          (a, b) => b.totalInBase.amount.compareTo(a.totalInBase.amount),
        );
    if (assetAllocations.isEmpty) return const SizedBox.shrink();

    final total = assetAllocations.fold<Decimal>(
      Decimal.zero,
      (acc, a) => acc + a.totalInBase.amount,
    );
    if (total == Decimal.zero) return const SizedBox.shrink();

    final palette = ChartPalette.of(context);
    final segments = <_AllocationSegment>[];
    final topAllocations = assetAllocations.take(3).toList(growable: false);
    for (var i = 0; i < topAllocations.length; i++) {
      final allocation = topAllocations[i];
      final amount = allocation.totalInBase.amount;
      final ratio = (amount / total).toDouble();
      segments.add(
        _AllocationSegment(
          label: AssetCategoryVisuals.label(l10n, allocation.category),
          amount: amount,
          ratio: ratio,
          color: palette.accentAt(i),
        ),
      );
    }
    final otherAllocations = assetAllocations.skip(3).toList(growable: false);
    if (otherAllocations.isNotEmpty) {
      final amount = otherAllocations.fold<Decimal>(
        Decimal.zero,
        (acc, allocation) => acc + allocation.totalInBase.amount,
      );
      final ratio = (amount / total).toDouble();
      segments.add(
        _AllocationSegment(
          label: l10n.cashFlowKindOther,
          amount: amount,
          ratio: ratio,
          color: colors.mutedForeground.withValues(alpha: AppOpacity.muted),
        ),
      );
    }

    final barSegments = <_AllocationSegment>[];
    for (var i = 0; i < assetAllocations.length; i++) {
      final allocation = assetAllocations[i];
      final ratio = (allocation.totalInBase.amount / total).toDouble();
      barSegments.add(
        _AllocationSegment(
          label: AssetCategoryVisuals.label(l10n, allocation.category),
          amount: allocation.totalInBase.amount,
          ratio: ratio,
          color: palette.accentAt(i),
        ),
      );
    }

    return HomeSection(
      title: l10n.dashboardAllocationSummaryTitle,
      actionLabel: l10n.dashboardAllocationViewBreakdown,
      onAction: () =>
          showAllocationDetailPanel(context: context, snapshot: snapshot),
      child: HomeSurface(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StackedBar(segments: barSegments),
            const SizedBox(height: AppSpacing.s14),
            for (var i = 0; i < segments.length; i++) ...[
              _SegmentLegendRow(
                segment: segments[i],
                baseCurrency: snapshot.baseCurrency,
              ),
              if (i < segments.length - 1)
                const SizedBox(height: AppSpacing.s8),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllocationSegment {
  const _AllocationSegment({
    required this.label,
    required this.amount,
    required this.ratio,
    required this.color,
  });

  final String label;
  final Decimal amount;
  final double ratio;
  final Color color;
}

class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.segments});

  final List<_AllocationSegment> segments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: SizedBox(
        height: AppSpacing.s8,
        child: Row(
          children: [
            for (final s in segments)
              Expanded(
                flex: (s.ratio * 1000).round().clamp(1, 1000),
                child: Container(color: s.color),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentLegendRow extends StatelessWidget {
  const _SegmentLegendRow({required this.segment, required this.baseCurrency});

  final _AllocationSegment segment;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final pct = (segment.ratio * 100).clamp(0, 100).toStringAsFixed(1);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: segment.color,
            borderRadius: BorderRadius.circular(AppRadius.xxs),
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Text(
            segment.label,
            style: context.theme.typography.body.sm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyText(
              amount: segment.amount.toDouble(),
              currencyCode: baseCurrency,
              compact: true,
              style: context.labelStyle,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              '$pct%',
              style: context.captionStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
