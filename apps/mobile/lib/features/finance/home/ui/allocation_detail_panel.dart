import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/liabilities/ui/liability_l10n.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/dashboard_models.dart';
import 'asset_category_visuals.dart';

part 'allocation_detail_panel_breakdown.dart';
part 'allocation_detail_panel_controls.dart';
part 'allocation_detail_panel_donut.dart';
part 'allocation_detail_panel_models.dart';

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
    transitionDuration: AppMotionPolicy.duration(
      context,
      Motion.medium,
      role: AppMotionRole.transition,
    ),
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
                    style: context.theme.typography.body.lg,
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
