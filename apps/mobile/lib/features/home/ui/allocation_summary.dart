import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/dashboard_models.dart';
import 'allocation_detail_panel.dart';
import 'asset_category_visuals.dart';

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
    for (var i = 0; i < assetAllocations.length; i++) {
      final allocation = assetAllocations[i];
      final ratio = (allocation.totalInBase.amount / total).toDouble();
      segments.add(
        _AllocationSegment(
          allocation: allocation,
          ratio: ratio,
          color: palette.accentAt(i),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.s4, top: AppSpacing.s4, bottom: AppSpacing.s8),
          child: Text(
            l10n.dashboardAllocationSummaryTitle,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
        SoftCard(
          padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s16, AppSpacing.s16, AppSpacing.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StackedBar(segments: segments),
              const SizedBox(height: 14),
              for (final s in segments.take(3)) ...[
                _SegmentLegendRow(
                  segment: s,
                  baseCurrency: snapshot.baseCurrency,
                ),
                if (s != segments.take(3).last) const SizedBox(height: AppSpacing.s8),
              ],
              const SizedBox(height: AppSpacing.s4),
              Align(
                alignment: Alignment.centerLeft,
                child: FTappable(
                  onPress: () => showAllocationDetailPanel(
                    context: context,
                    snapshot: snapshot,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Text(
                      l10n.dashboardAllocationViewBreakdown,
                      style: context.theme.typography.xs.copyWith(
                        color: context.theme.colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AllocationSegment {
  const _AllocationSegment({
    required this.allocation,
    required this.ratio,
    required this.color,
  });

  final CategoryAllocation allocation;
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
        height: 8,
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
    final l10n = AppLocalizations.of(context);
    final pct = (segment.ratio * 100).clamp(0, 100).toStringAsFixed(1);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: segment.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            AssetCategoryVisuals.label(l10n, segment.allocation.category),
            style: context.theme.typography.sm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$pct%',
          style: context.theme.typography.sm.copyWith(
            color: context.theme.colors.mutedForeground,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
