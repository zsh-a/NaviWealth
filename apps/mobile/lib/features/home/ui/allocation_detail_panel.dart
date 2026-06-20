import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../liabilities/ui/liability_l10n.dart';
import '../domain/dashboard_models.dart';
import 'asset_category_visuals.dart';

enum _AllocationDimension { assetClass, currency }

Future<void> showAllocationDetailPanel({
  required BuildContext context,
  required DashboardSnapshot snapshot,
}) async {
  await SchedulerBinding.instance.endOfFrame;
  if (!context.mounted) return;

  final width = MediaQuery.sizeOf(context).width;
  if (Breakpoints.isMobile(width)) {
    final l10n = AppLocalizations.of(context);
    return showAppSheet<void>(
      context: context,
      title: l10n.dashboardAllocationTitle,
      maxHeightFactor: 0.92,
      actions: [
        FButton.icon(
          variant: FButtonVariant.ghost,
          onPress: () => _deferredMaybePop(context),
          child: const Icon(FLucideIcons.x, size: AppIconSizes.h18),
        ),
      ],
      builder: (_) => _AllocationDetailBody(
        snapshot: snapshot,
        expandList: false,
        showHandle: false,
        showTitle: false,
      ),
    );
  }

  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'allocation-detail-panel',
    barrierDismissible: true,
    barrierColor: SemanticColors.of(context).scrim,
    transitionDuration: Motion.medium,
    pageBuilder: (_, _, _) => _DesktopAllocationInspector(snapshot: snapshot),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.standardDecelerate,
        reverseCurve: Motion.standardAccelerate,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _DesktopAllocationInspector extends StatelessWidget {
  const _DesktopAllocationInspector({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        left: false,
        child: Container(
          width: 430,
          height: double.infinity,
          decoration: BoxDecoration(
            color: colors.background,
            border: Border(left: BorderSide(color: colors.border)),
            boxShadow: AppShadow.panel,
          ),
          child: _AllocationDetailBody(snapshot: snapshot),
        ),
      ),
    );
  }
}

class _AllocationDetailBody extends StatefulWidget {
  const _AllocationDetailBody({
    required this.snapshot,
    this.expandList = true,
    this.showHandle = false,
    this.showTitle = true,
  });

  final DashboardSnapshot snapshot;
  final bool expandList;
  final bool showHandle;
  final bool showTitle;

  @override
  State<_AllocationDetailBody> createState() => _AllocationDetailBodyState();
}

class _AllocationDetailBodyState extends State<_AllocationDetailBody> {
  _AllocationDimension _dimension = _AllocationDimension.assetClass;
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _groupsFor(widget.snapshot, _dimension, l10n);
    final selected = groups.isEmpty
        ? null
        : groups.firstWhere(
            (g) => g.key == _selectedKey,
            orElse: () => groups.first,
          );
    final total = groups.fold<double>(0, (sum, g) => sum + g.value);

    final content = <Widget>[
      _AllocationDonut(
        groups: groups,
        total: total,
        currencyCode: widget.snapshot.baseCurrency,
      ),
      const SizedBox(height: AppSpacing.s20),
      for (final group in groups)
        _BreakdownRow(
          group: group,
          total: total,
          baseCurrency: widget.snapshot.baseCurrency,
          selected: selected?.key == group.key,
          onTap: () => setState(() => _selectedKey = group.key),
        ),
      if (selected != null) ...[
        const SizedBox(height: AppSpacing.s20),
        _DrillDownList(
          group: selected,
          baseCurrency: widget.snapshot.baseCurrency,
        ),
      ],
    ];

    const contentPadding = EdgeInsets.fromLTRB(
      AppSpacing.s20,
      18,
      AppSpacing.s20,
      AppSpacing.s24,
    );
    final list = widget.expandList
        ? ListView(padding: contentPadding, children: content)
        : Padding(
            padding: contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: content,
            ),
          );

    return Column(
      mainAxisSize: widget.expandList ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHandle) AppSheetDragHandle(colors: context.theme.colors),
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s14,
              AppSpacing.s12,
              AppSpacing.s8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.dashboardAllocationTitle,
                    style: context.theme.typography.lg,
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: () => _deferredMaybePop(context),
                  child: const Icon(FLucideIcons.x, size: AppIconSizes.h18),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
          child: _DimensionSwitch(
            value: _dimension,
            onChanged: (value) {
              setState(() {
                _dimension = value;
                _selectedKey = null;
              });
            },
          ),
        ),
        if (widget.expandList) Expanded(child: list) else list,
      ],
    );
  }
}

Future<void> _deferredMaybePop(BuildContext context) async {
  await SchedulerBinding.instance.endOfFrame;
  if (!context.mounted) return;
  await Navigator.of(context).maybePop();
}

class _DimensionSwitch extends StatelessWidget {
  const _DimensionSwitch({required this.value, required this.onChanged});

  final _AllocationDimension value;
  final ValueChanged<_AllocationDimension> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      _AllocationDimension.assetClass: l10n.portfolioViewClass,
      _AllocationDimension.currency: l10n.portfolioViewCurrency,
    };
    final icons = {
      _AllocationDimension.assetClass: FLucideIcons.layoutGrid,
      _AllocationDimension.currency: FLucideIcons.arrowLeftRight,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(
          alpha: AppOpacity.scrim,
        ),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s2),
        child: Row(
          children: [
            for (final dimension in _AllocationDimension.values)
              Expanded(
                child: _DimensionButton(
                  label: labels[dimension]!,
                  icon: icons[dimension]!,
                  selected: value == dimension,
                  onTap: () => onChanged(dimension),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DimensionButton extends StatelessWidget {
  const _DimensionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    return FTappable(
      onPress: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standardDecelerate,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        decoration: BoxDecoration(
          color: selected
              ? context.theme.colors.background
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: selected ? AppShadow.elevation1 : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: AppIconSizes.sm, color: color),
            const SizedBox(width: AppSpacing.s6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: selected
                    ? context.captionLabelStyle.copyWith(color: color)
                    : context.captionMediumStyle.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllocationDonut extends StatelessWidget {
  const _AllocationDonut({
    required this.groups,
    required this.total,
    required this.currencyCode,
  });

  final List<_AllocationGroup> groups;
  final double total;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppChartHeights.allocationDonut,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: const Size.square(220),
              painter: _DonutPainter(
                groups: groups,
                total: total,
                trackColor: context.theme.colors.border.withValues(
                  alpha: AppOpacity.light,
                ),
              ),
            ),
          ),
          SizedBox(
            width: AppControlWidths.donutCenterLabel,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoneyText(
                  amount: total,
                  currencyCode: currencyCode,
                  compact: true,
                  style: context.strongTitleStyle,
                ),
                Text(
                  AppLocalizations.of(context).assetsAppBarTitle,
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.groups,
    required this.total,
    required this.trackColor,
  });

  final List<_AllocationGroup> groups;
  final double total;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = math.min(size.width, size.height) * 0.13;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;

    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, track);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final group in groups) {
      final sweep = (group.value / total) * math.pi * 2;
      paint.color = group.color;
      canvas.drawArc(rect.deflate(stroke / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.groups != groups || oldDelegate.total != total;
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.group,
    required this.total,
    required this.baseCurrency,
    required this.selected,
    required this.onTap,
  });

  final _AllocationGroup group;
  final double total;
  final String baseCurrency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0 : (group.value / total) * 100;
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: FTappable(
        onPress: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.faint)
                : colors.foreground.withValues(alpha: AppOpacity.whisper),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: AppOpacity.muted)
                  : colors.foreground.withValues(alpha: AppOpacity.faint),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s10,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: group.color.withValues(alpha: AppOpacity.medium),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    group.icon,
                    size: AppIconSizes.h18,
                    color: group.color,
                  ),
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Text(
                    group.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.labelStyle,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      amount: group.value,
                      currencyCode: baseCurrency,
                      compact: true,
                      style: context.labelStyle,
                    ),
                    Text(
                      '${pct.toStringAsFixed(pct >= 10 ? 0 : 1)}%',
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrillDownList extends StatelessWidget {
  const _DrillDownList({required this.group, required this.baseCurrency});

  final _AllocationGroup group;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.dashboardDrillDownItemCount(group.items.length),
          style: context.captionLabelStyle.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        for (final item in group.items)
          FTile(
            prefix: Icon(group.icon, color: group.color),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _subtitle(l10n, item) == null
                ? null
                : Text(
                    _subtitle(l10n, item)!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            suffix: MoneyText(
              amount: item.valueInBase.amount.toDouble(),
              currencyCode: baseCurrency,
              compact: true,
            ),
            onPress: item.routeHint == null
                ? null
                : () => context.push(item.routeHint!),
          ),
      ],
    );
  }

  String? _subtitle(AppLocalizations l10n, CategoryItem item) {
    if (item.liabilityType != null) {
      return liabilityTypeLabel(l10n, item.liabilityType!);
    }
    return item.subtitle;
  }
}

class _AllocationGroup {
  const _AllocationGroup({
    required this.key,
    required this.label,
    required this.value,
    required this.items,
    required this.icon,
    required this.color,
  });

  final String key;
  final String label;
  final double value;
  final List<CategoryItem> items;
  final IconData icon;
  final Color color;
}

List<_AllocationGroup> _groupsFor(
  DashboardSnapshot snapshot,
  _AllocationDimension dimension,
  AppLocalizations l10n,
) {
  final assetAllocations = snapshot.allocations.where((a) => !a.isLiability);
  final paletteSeed = _PaletteSeed();

  if (dimension == _AllocationDimension.assetClass) {
    return [
      for (final allocation in assetAllocations)
        _AllocationGroup(
          key: allocation.category.name,
          label: AssetCategoryVisuals.label(l10n, allocation.category),
          value: allocation.totalInBase.amount.toDouble(),
          items: allocation.items,
          icon: AssetCategoryVisuals.icon(allocation.category),
          color: paletteSeed.next(),
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
  }

  final byCurrency = <String, List<CategoryItem>>{};
  for (final allocation in assetAllocations) {
    for (final item in allocation.items) {
      byCurrency.putIfAbsent(item.nativeCurrency, () => []).add(item);
    }
  }

  return [
    for (final entry in byCurrency.entries)
      _AllocationGroup(
        key: entry.key,
        label: entry.key,
        value: entry.value.fold<double>(
          0,
          (sum, item) => sum + item.valueInBase.amount.toDouble(),
        ),
        items: entry.value
          ..sort(
            (a, b) => b.valueInBase.amount.compareTo(a.valueInBase.amount),
          ),
        icon: FLucideIcons.arrowLeftRight,
        color: paletteSeed.next(),
      ),
  ]..sort((a, b) => b.value.compareTo(a.value));
}

class _PaletteSeed {
  var _index = 0;

  Color next() {
    const colors = [
      ColorPalette.cyanBrand500,
      ColorPalette.brand400,
      ExpenseCategoryColors.amberLight,
      ColorPalette.red500,
      ExpenseCategoryColors.violet,
      ColorPalette.green500,
      ExpenseCategoryColors.pink,
      ColorPalette.neutral600,
    ];
    final color = colors[_index % colors.length];
    _index += 1;
    return color;
  }
}
