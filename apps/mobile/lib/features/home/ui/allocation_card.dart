import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../liabilities/ui/liability_l10n.dart';
import '../domain/dashboard_models.dart';
import 'asset_category_visuals.dart';
import 'dashboard_chart_fullscreen.dart';

/// Asset-allocation card: a Sankey-style flow of category totals into gross
/// assets, then into net worth / liability deductions.
class AllocationCard extends StatelessWidget {
  const AllocationCard({super.key, required this.snapshot, this.onSliceTap});

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

    return FCard.raw(
      child: Padding(
        padding: Spacing.cardHero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= Breakpoints.mobile;
            final chart = _AllocationSankeyChart(
              assetAllocs: assetAllocs,
              liabilityAlloc: liabilityAlloc,
              snapshot: snapshot,
              height: isWide ? 260 : 300,
              onTap: (alloc) => _openDrillDown(context, alloc),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.dashboardAllocationTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.aiChatSheetExpandTooltip,
                      icon: const Icon(Icons.fullscreen),
                      onPressed: () => _openFullscreen(context),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.s8),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: chart),
                      const SizedBox(width: Spacing.s24),
                      Expanded(flex: 5, child: legend),
                    ],
                  )
                else ...[
                  chart,
                  const SizedBox(height: Spacing.s12),
                  legend,
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assetAllocs = snapshot.allocations
        .where((a) => !a.isLiability)
        .toList(growable: false);
    final liabilityAlloc = snapshot.allocations
        .where((a) => a.isLiability)
        .cast<CategoryAllocation?>()
        .firstWhere((a) => true, orElse: () => null);
    showDashboardChartFullscreen(
      context: context,
      title: l10n.dashboardAllocationTitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= Breakpoints.mobile;
          return isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _AllocationSankeyChart(
                        assetAllocs: assetAllocs,
                        liabilityAlloc: liabilityAlloc,
                        snapshot: snapshot,
                        height: math.max(360, constraints.maxHeight - 32),
                        onTap: (alloc) => _openDrillDown(context, alloc),
                      ),
                    ),
                    const SizedBox(width: Spacing.s24),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        child: _Legend(
                          assetAllocs: assetAllocs,
                          liabilityAlloc: liabilityAlloc,
                          snapshot: snapshot,
                          onTap: (alloc) => _openDrillDown(context, alloc),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  children: [
                    _AllocationSankeyChart(
                      assetAllocs: assetAllocs,
                      liabilityAlloc: liabilityAlloc,
                      snapshot: snapshot,
                      height: math.max(360, constraints.maxHeight * 0.58),
                      onTap: (alloc) => _openDrillDown(context, alloc),
                    ),
                    const SizedBox(height: Spacing.s16),
                    _Legend(
                      assetAllocs: assetAllocs,
                      liabilityAlloc: liabilityAlloc,
                      snapshot: snapshot,
                      onTap: (alloc) => _openDrillDown(context, alloc),
                    ),
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
    showModalBottomSheet<void>(
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

class _AllocationSankeyChart extends StatelessWidget {
  const _AllocationSankeyChart({
    required this.assetAllocs,
    required this.liabilityAlloc,
    required this.snapshot,
    required this.height,
    required this.onTap,
  });

  final List<CategoryAllocation> assetAllocs;
  final CategoryAllocation? liabilityAlloc;
  final DashboardSnapshot snapshot;
  final double height;
  final void Function(CategoryAllocation) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ChartPalette.of(context);
    final valueAxis = ValueAxis.currency(currencyCode: snapshot.baseCurrency);
    final flows = <_SankeyFlow>[
      for (var i = 0; i < assetAllocs.length; i++)
        if (assetAllocs[i].totalInBase.amount.toDouble() > 0)
          _SankeyFlow(
            label: AssetCategoryVisuals.label(l10n, assetAllocs[i].category),
            value: assetAllocs[i].totalInBase.amount.toDouble(),
            valueLabel: valueAxis.formatValue(
              assetAllocs[i].totalInBase.amount.toDouble(),
            ),
            color: palette.accentAt(i),
            allocation: assetAllocs[i],
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final liabilityValue =
        liabilityAlloc?.totalInBase.amount.toDouble().abs() ?? 0;

    if (flows.isEmpty && liabilityValue == 0) {
      return SizedBox(
        height: height,
        child: const EmptyChartPlaceholder(icon: Icons.account_tree_outlined),
      );
    }

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final hit = _SankeyLayout.compute(
                size: Size(constraints.maxWidth, height),
                flows: flows,
                liabilityValue: liabilityValue,
              ).hitTest(details.localPosition, flows, liabilityAlloc);
              if (hit != null) onTap(hit);
            },
            child: CustomPaint(
              painter: _SankeyPainter(
                flows: flows,
                totalAssetsLabel: l10n.assetsAppBarTitle,
                totalAssetsValueLabel: valueAxis.formatValue(
                  snapshot.totalAssets.amount.toDouble(),
                ),
                netWorthLabel: l10n.homeNetWorthTitle,
                netWorthValue: snapshot.netWorth.amount
                    .toDouble()
                    .clamp(0.0, double.infinity)
                    .toDouble(),
                netWorthValueLabel: valueAxis.formatValue(
                  snapshot.netWorth.amount.toDouble(),
                ),
                liabilityLabel: l10n.dashboardCategoryLiability,
                liabilityValue: liabilityValue,
                liabilityValueLabel: valueAxis.formatValue(liabilityValue),
                liabilityAllocation: liabilityAlloc,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _SankeyFlow {
  const _SankeyFlow({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.color,
    required this.allocation,
  });

  final String label;
  final double value;
  final String valueLabel;
  final Color color;
  final CategoryAllocation allocation;
}

class _SankeyLayout {
  const _SankeyLayout({
    required this.sourceRects,
    required this.assetRect,
    required this.netWorthRect,
    required this.liabilityRect,
    required this.assetOutRect,
    required this.netWorthInRect,
    required this.liabilityOutRect,
    required this.liabilityInRect,
  });

  final List<Rect> sourceRects;
  final Rect assetRect;
  final Rect netWorthRect;
  final Rect? liabilityRect;
  final Rect assetOutRect;
  final Rect netWorthInRect;
  final Rect? liabilityOutRect;
  final Rect? liabilityInRect;

  static _SankeyLayout compute({
    required Size size,
    required List<_SankeyFlow> flows,
    required double liabilityValue,
  }) {
    const nodeWidth = 12.0;
    const top = 16.0;
    final bottom = size.height - 16.0;
    final available = math.max(1.0, bottom - top);
    final totalAssets = flows.fold<double>(0, (sum, f) => sum + f.value);
    final total = math.max(totalAssets, 1);
    final gap = flows.length > 1 ? 8.0 : 0.0;
    final sourceAvailable = math.max(
      1.0,
      available - gap * math.max(0, flows.length - 1),
    );
    final sourceRects = <Rect>[];
    var cursor = top;
    for (final flow in flows) {
      final h = math.max(12.0, sourceAvailable * flow.value / total);
      sourceRects.add(Rect.fromLTWH(0, cursor, nodeWidth, h));
      cursor += h + gap;
    }

    final centerX = size.width * 0.58;
    final rightX = size.width - nodeWidth;
    final assetRect = Rect.fromLTWH(centerX, top, nodeWidth, available);
    final liabilityRatio = liabilityValue <= 0 ? 0.0 : liabilityValue / total;
    final liabilityHeight = liabilityValue <= 0
        ? 0.0
        : math.max(24.0, available * liabilityRatio);
    final netWorthHeight = liabilityValue <= 0
        ? available
        : math.max(24.0, available - liabilityHeight - 10);
    final netWorthRect = Rect.fromLTWH(rightX, top, nodeWidth, netWorthHeight);
    final liabilityRect = liabilityValue <= 0
        ? null
        : Rect.fromLTWH(
            rightX,
            bottom - liabilityHeight,
            nodeWidth,
            liabilityHeight,
          );
    final assetOutRect = Rect.fromLTWH(centerX + nodeWidth, top, 1, available);
    final netWorthInRect = Rect.fromLTWH(rightX - 1, top, 1, netWorthHeight);
    final liabilityOutRect = liabilityValue <= 0
        ? null
        : Rect.fromLTWH(
            centerX + nodeWidth,
            bottom - liabilityHeight,
            1,
            liabilityHeight,
          );
    final liabilityInRect = liabilityRect == null
        ? null
        : Rect.fromLTWH(rightX - 1, liabilityRect.top, 1, liabilityHeight);
    return _SankeyLayout(
      sourceRects: sourceRects,
      assetRect: assetRect,
      netWorthRect: netWorthRect,
      liabilityRect: liabilityRect,
      assetOutRect: assetOutRect,
      netWorthInRect: netWorthInRect,
      liabilityOutRect: liabilityOutRect,
      liabilityInRect: liabilityInRect,
    );
  }

  CategoryAllocation? hitTest(
    Offset point,
    List<_SankeyFlow> flows,
    CategoryAllocation? liabilityAllocation,
  ) {
    for (var i = 0; i < sourceRects.length && i < flows.length; i++) {
      final hitRect = Rect.fromLTRB(
        sourceRects[i].left,
        sourceRects[i].top - 4,
        assetRect.left,
        sourceRects[i].bottom + 4,
      );
      if (hitRect.contains(point)) return flows[i].allocation;
    }
    if (liabilityAllocation != null &&
        liabilityRect != null &&
        Rect.fromLTRB(
          assetRect.right,
          liabilityRect!.top - 8,
          liabilityRect!.right,
          liabilityRect!.bottom + 8,
        ).contains(point)) {
      return liabilityAllocation;
    }
    return null;
  }
}

class _SankeyPainter extends CustomPainter {
  const _SankeyPainter({
    required this.flows,
    required this.totalAssetsLabel,
    required this.totalAssetsValueLabel,
    required this.netWorthLabel,
    required this.netWorthValue,
    required this.netWorthValueLabel,
    required this.liabilityLabel,
    required this.liabilityValue,
    required this.liabilityValueLabel,
    required this.liabilityAllocation,
  });

  final List<_SankeyFlow> flows;
  final String totalAssetsLabel;
  final String totalAssetsValueLabel;
  final String netWorthLabel;
  final double netWorthValue;
  final String netWorthValueLabel;
  final String liabilityLabel;
  final double liabilityValue;
  final String liabilityValueLabel;
  final CategoryAllocation? liabilityAllocation;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _SankeyLayout.compute(
      size: size,
      flows: flows,
      liabilityValue: liabilityValue,
    );
    final totalAssets = flows.fold<double>(0, (sum, f) => sum + f.value);
    final nodePaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < flows.length; i++) {
      final flow = flows[i];
      final source = layout.sourceRects[i];
      final targetHeight =
          layout.assetRect.height * (flow.value / math.max(totalAssets, 1));
      final previous = flows
          .take(i)
          .fold<double>(
            0,
            (sum, f) => sum + f.value / math.max(totalAssets, 1),
          );
      final target = Rect.fromLTWH(
        layout.assetRect.left,
        layout.assetRect.top + layout.assetRect.height * previous,
        layout.assetRect.width,
        targetHeight,
      );
      _drawRibbon(canvas, source, target, flow.color.withValues(alpha: 0.28));
      nodePaint.color = flow.color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(source, const Radius.circular(4)),
        nodePaint,
      );
      _drawLabel(
        canvas,
        Offset(source.right + 8, source.top - 1),
        flow.label,
        flow.valueLabel,
        size.width * 0.34,
      );
    }

    nodePaint.color = const Color(0xFF64748B);
    canvas.drawRRect(
      RRect.fromRectAndRadius(layout.assetRect, const Radius.circular(4)),
      nodePaint,
    );
    _drawLabel(
      canvas,
      Offset(layout.assetRect.left - 54, layout.assetRect.top),
      totalAssetsLabel,
      totalAssetsValueLabel,
      50,
      align: TextAlign.right,
    );

    final netWorthOutHeight = liabilityValue <= 0
        ? layout.assetRect.height
        : layout.netWorthRect.height;
    final netWorthOut = Rect.fromLTWH(
      layout.assetOutRect.left,
      layout.assetRect.top,
      1,
      netWorthOutHeight,
    );
    _drawRibbon(
      canvas,
      netWorthOut,
      layout.netWorthInRect,
      const Color(0xFF22C55E).withValues(alpha: 0.24),
    );
    nodePaint.color = const Color(0xFF22C55E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(layout.netWorthRect, const Radius.circular(4)),
      nodePaint,
    );
    _drawLabel(
      canvas,
      Offset(layout.netWorthRect.left - 96, layout.netWorthRect.top),
      netWorthLabel,
      netWorthValueLabel,
      88,
      align: TextAlign.right,
    );

    if (liabilityValue > 0 &&
        layout.liabilityRect != null &&
        layout.liabilityOutRect != null &&
        layout.liabilityInRect != null) {
      _drawRibbon(
        canvas,
        layout.liabilityOutRect!,
        layout.liabilityInRect!,
        const Color(0xFFEF4444).withValues(alpha: 0.22),
      );
      nodePaint.color = const Color(0xFFEF4444);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          layout.liabilityRect!,
          const Radius.circular(4),
        ),
        nodePaint,
      );
      _drawLabel(
        canvas,
        Offset(layout.liabilityRect!.left - 96, layout.liabilityRect!.top),
        liabilityLabel,
        liabilityValueLabel,
        88,
        align: TextAlign.right,
      );
    }
  }

  void _drawRibbon(Canvas canvas, Rect from, Rect to, Color color) {
    final path = Path()
      ..moveTo(from.right, from.top)
      ..cubicTo(
        from.right + 48,
        from.top,
        to.left - 48,
        to.top,
        to.left,
        to.top,
      )
      ..lineTo(to.left, to.bottom)
      ..cubicTo(
        to.left - 48,
        to.bottom,
        from.right + 48,
        from.bottom,
        from.right,
        from.bottom,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawLabel(
    Canvas canvas,
    Offset offset,
    String label,
    String value,
    double maxWidth, {
    TextAlign align = TextAlign.left,
  }) {
    final title = TextPainter(
      text: TextSpan(
        text: label,
        style: TypographyTokens.numericCaption.copyWith(
          color: const Color(0xFF64748B),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    title.paint(canvas, offset);
    final subtitle = TextPainter(
      text: TextSpan(
        text: value,
        style: TypographyTokens.numericCaption.copyWith(
          color: const Color(0xFF94A3B8),
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    subtitle.paint(canvas, offset.translate(0, title.height + 1));
  }

  @override
  bool shouldRepaint(covariant _SankeyPainter oldDelegate) =>
      oldDelegate.flows != flows ||
      oldDelegate.liabilityValue != liabilityValue ||
      oldDelegate.netWorthValue != netWorthValue;
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
    // Percent denominator: sum of positive category totals only, so
    // negative cash doesn't inflate other categories past 100%.
    final positiveTotal = assetAllocs
        .map((a) => a.totalInBase.amount.toDouble())
        .where((v) => v > 0)
        .fold<double>(0, (a, b) => a + b);

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
            percent: positiveTotal == 0
                ? 0
                : assetAllocs[i].totalInBase.amount.toDouble() / positiveTotal,
            onTap: () => onTap(assetAllocs[i]),
          ),
        if (liabilityAlloc != null) ...[
          const SizedBox(height: Spacing.s8),
          const FDivider(),
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
    final pctText = percent == null
        ? null
        : '${(percent! * 100).toStringAsFixed(1)}%';
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
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
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
                  return FTile(
                    title: Text(item.name),
                    prefix: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        AssetCategoryVisuals.icon(allocation.category),
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    subtitle: _itemSubtitle(l10n, item) == null
                        ? null
                        : Text(_itemSubtitle(l10n, item)!),
                    suffix: Column(
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
                    onPress: item.routeHint == null
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
