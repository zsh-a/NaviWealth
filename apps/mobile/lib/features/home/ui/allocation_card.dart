import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../liabilities/ui/liability_l10n.dart';
import '../domain/dashboard_models.dart';
import 'asset_category_visuals.dart';


/// Asset-allocation card: a donut chart of category totals plus a
/// tappable legend that drills into the category's underlying assets.
///
/// The pie chart slices are rendered with the standard [NwPieChart]
/// wrapper so theme + dark-mode + accessibility behave identically to
/// every other chart in the app.
class AllocationCard extends StatelessWidget {
  const AllocationCard({
    super.key,
    required this.snapshot,
    this.onSliceTap,
  });

  final DashboardSnapshot snapshot;

  /// Optional override for the drill-down handler. When null the card
  /// shows a bottom sheet listing the category's items; tests inject a
  /// custom handler to capture the selection without spinning up a
  /// Navigator.
  final void Function(BuildContext context, CategoryAllocation alloc)?
      onSliceTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final assetAllocs = snapshot.allocations
        .where((a) => !a.isLiability)
        .toList(growable: false);
    final liabilityAlloc = snapshot.allocations
        .where((a) => a.isLiability)
        .cast<CategoryAllocation?>()
        .firstWhere((a) => true, orElse: () => null);

    final slices = [
      for (var i = 0; i < assetAllocs.length; i++)
        Slice(
          label: AssetCategoryVisuals.label(l10n, assetAllocs[i].category),
          value: assetAllocs[i].totalInBase.amount.toDouble(),
          colorOverride: ChartPalette.of(context).accentAt(i),
          meta: assetAllocs[i],
        ),
    ];

    return LiquidGlassCard(
      padding: Spacing.cardHero,
      child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= Breakpoints.mobile;
            final pie = _PieSection(
              slices: slices,
              onTapSlice: (slice) {
                final alloc = slice.meta;
                if (alloc is! CategoryAllocation) return;
                _openDrillDown(context, alloc);
              },
            );
            final legend = _Legend(
              assetAllocs: assetAllocs,
              liabilityAlloc: liabilityAlloc,
              snapshot: snapshot,
              onTap: (alloc) => _openDrillDown(context, alloc),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dashboardAllocationTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Spacing.s12),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: pie),
                      const SizedBox(width: Spacing.s24),
                      Expanded(child: legend),
                    ],
                  )
                else ...[
                  pie,
                  const SizedBox(height: Spacing.s12),
                  legend,
                ],
              ],
            );
          },
        ),
    );
  }

  void _openDrillDown(BuildContext context, CategoryAllocation alloc) {
    if (onSliceTap != null) {
      onSliceTap!(context, alloc);
      return;
    }
    showGlassModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => CategoryDrillDownSheet(
        allocation: alloc,
        baseCurrency: snapshot.baseCurrency,
      ),
    );
  }
}

class _PieSection extends StatelessWidget {
  const _PieSection({required this.slices, required this.onTapSlice});

  final List<Slice> slices;
  final void Function(Slice) onTapSlice;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return const AspectRatio(
        aspectRatio: 1,
        child: EmptyChartPlaceholder(icon: Icons.donut_large),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: NwPieChart(
        slices: slices,
        drillDown: SliceDrillDown(onTapSlice),
        semanticLabel: AppLocalizations.of(context).dashboardAllocationTitle,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.assetAllocs,
    required this.liabilityAlloc,
    required this.snapshot,
    required this.onTap,
  });

  final List<CategoryAllocation> assetAllocs;
  final CategoryAllocation? liabilityAlloc;
  final DashboardSnapshot snapshot;
  final void Function(CategoryAllocation) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ChartPalette.of(context);
    final assetTotal = snapshot.totalAssets.amount.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < assetAllocs.length; i++)
          _LegendRow(
            color: palette.accentAt(i),
            label: AssetCategoryVisuals.label(l10n, assetAllocs[i].category),
            icon: AssetCategoryVisuals.icon(assetAllocs[i].category),
            valueInBase: assetAllocs[i].totalInBase.amount.toDouble(),
            currencyCode: snapshot.baseCurrency,
            percent: assetTotal == 0
                ? 0
                : assetAllocs[i].totalInBase.amount.toDouble() / assetTotal,
            onTap: () => onTap(assetAllocs[i]),
          ),
        if (liabilityAlloc != null) ...[
          const SizedBox(height: Spacing.s8),
          const Divider(height: 1),
          const SizedBox(height: Spacing.s8),
          _LegendRow(
            color: Theme.of(context).colorScheme.error,
            label: AssetCategoryVisuals.label(l10n, liabilityAlloc!.category),
            icon: AssetCategoryVisuals.icon(liabilityAlloc!.category),
            valueInBase: -liabilityAlloc!.totalInBase.amount.toDouble(),
            currencyCode: snapshot.baseCurrency,
            percent: null,
            onTap: () => onTap(liabilityAlloc!),
          ),
        ],
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.icon,
    required this.valueInBase,
    required this.currencyCode,
    required this.percent,
    required this.onTap,
  });

  final Color color;
  final String label;
  final IconData icon;
  final double valueInBase;
  final String currencyCode;
  final double? percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pctText =
        percent == null ? null : '${(percent! * 100).toStringAsFixed(1)}%';
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          // Material 48dp touch-target floor — the visual row is shorter
          // than this, so the InkWell pads itself out vertically.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Spacing.s12,
              horizontal: Spacing.s8,
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: Spacing.s8),
                Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Spacing.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodyMedium),
                      if (pctText != null)
                        Text(
                          pctText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                MoneyText(
                  amount: valueInBase,
                  currencyCode: currencyCode,
                  compact: true,
                  showSign: valueInBase < 0,
                ),
                const SizedBox(width: Spacing.s4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet (mobile) / dialog body (wide) listing the assets that
/// roll up into a tapped pie slice. Tapping a row deep-links to the
/// asset's detail page.
class CategoryDrillDownSheet extends StatelessWidget {
  const CategoryDrillDownSheet({
    super.key,
    required this.allocation,
    required this.baseCurrency,
  });

  final CategoryAllocation allocation;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isLiability = allocation.isLiability;
    final total = isLiability
        ? -allocation.totalInBase.amount.toDouble()
        : allocation.totalInBase.amount.toDouble();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.s16,
          Spacing.s8,
          Spacing.s16,
          Spacing.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  AssetCategoryVisuals.icon(allocation.category),
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: Spacing.s8),
                Expanded(
                  child: Text(
                    AssetCategoryVisuals.label(l10n, allocation.category),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                MoneyText(
                  amount: total,
                  currencyCode: baseCurrency,
                  showSign: total < 0,
                ),
              ],
            ),
            const SizedBox(height: Spacing.s8),
            Text(
              l10n.dashboardDrillDownItemCount(allocation.items.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.s8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allocation.items.length,
                itemBuilder: (ctx, i) {
                  final item = allocation.items[i];
                  final native = item.nativeAmount.toDouble();
                  final base = item.valueInBase.amount.toDouble();
                  final showFx = item.nativeCurrency != baseCurrency;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        AssetCategoryVisuals.icon(allocation.category),
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(item.name),
                    subtitle: _itemSubtitle(l10n, item) == null
                        ? null
                        : Text(_itemSubtitle(l10n, item)!),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        MoneyText(
                          amount: isLiability ? -base : base,
                          currencyCode: baseCurrency,
                          compact: true,
                          showSign: isLiability,
                        ),
                        if (showFx)
                          MoneyText(
                            amount: native,
                            currencyCode: item.nativeCurrency,
                            compact: true,
                            symbolStyle: MoneySymbolStyle.isoCode,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    onTap: item.routeHint == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            context.push(item.routeHint!);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Picks the localised secondary line for a drill-down row. Liability
  /// rows carry a [LiabilityType]; everything else uses the pre-rendered
  /// [CategoryItem.subtitle] (which the aggregator builds from rate /
  /// currency hints). Returns null when there's nothing meaningful to show.
  String? _itemSubtitle(AppLocalizations l10n, CategoryItem item) {
    if (item.liabilityType != null) {
      return liabilityTypeLabel(l10n, item.liabilityType!);
    }
    return item.subtitle;
  }
}
