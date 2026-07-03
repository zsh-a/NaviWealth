import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/core/ai/visual/ai_hover_overlay.dart';
import 'package:naviwealth/core/ai/visual/ai_object_capsule.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/liabilities/ui/liability_l10n.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/dashboard_models.dart';
import 'asset_category_visuals.dart';
import 'dashboard_chart_fullscreen.dart';

part 'allocation_card_drill_down.dart';
part 'allocation_card_legend.dart';
part 'allocation_card_sankey.dart';

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
    final l10n = AppLocalizations.of(context);

    final assetAllocs = snapshot.allocations
        .where((a) => !a.isLiability)
        .toList(growable: false);
    final liabilityAlloc = snapshot.allocations
        .where((a) => a.isLiability)
        .cast<CategoryAllocation?>()
        .firstWhere((a) => true, orElse: () => null);

    return AiContextChipScope(
      chips: <AiContextChip>[
        AiContextChip(
          key: 'chart',
          label: l10n.dashboardAllocationTitle,
          value: 'asset_allocation',
        ),
        AiContextChip(
          key: 'currency',
          label: snapshot.netWorth.currency,
          value: snapshot.netWorth.currency,
        ),
      ],
      child: AiHoverOverlay(
        capsule: AiObjectCapsule(
          source: 'home_allocation_card',
          intent: 'explain_chart',
          object: const AiObjectRef(type: 'chart', id: 'asset_allocation'),
          objectLabel: l10n.dashboardAllocationTitle,
        ),
        child: SoftCard(
          level: SoftCardLevel.raised,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s20),
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
                            style: context.theme.typography.body.md,
                          ),
                        ),
                        FTooltip(
                          tipBuilder: (_, _) =>
                              Text(l10n.aiChatSheetExpandTooltip),
                          child: FButton.icon(
                            variant: FButtonVariant.ghost,
                            onPress: () => _openFullscreen(context),
                            child: const Icon(
                              FLucideIcons.maximize,
                              size: AppIconSizes.md,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: chart),
                          const SizedBox(width: AppSpacing.s24),
                          Expanded(flex: 5, child: legend),
                        ],
                      )
                    else ...[
                      chart,
                      const SizedBox(height: AppSpacing.s12),
                      legend,
                    ],
                  ],
                );
              },
            ),
          ),
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
                    const SizedBox(width: AppSpacing.s24),
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
                    const SizedBox(height: AppSpacing.s16),
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
    final l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      title: AssetCategoryVisuals.label(l10n, alloc.category),
      builder: (ctx) => CategoryDrillDownSheet(
        allocation: alloc,
        baseCurrency: snapshot.baseCurrency,
        showHeader: false,
      ),
    );
  }
}
