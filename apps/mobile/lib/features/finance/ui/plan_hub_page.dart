import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';
import 'package:naviwealth/features/finance/investment/data/dca_plan_providers.dart';
import 'package:naviwealth/features/finance/life_events/data/financial_decision_providers.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/runway/data/money_runway_providers.dart';

import '../../../core/format/formatters.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/planning_hub_status.dart';
import '../composition/finance_route_paths.dart';

part 'plan_hub_entries.dart';

/// Plan hub intentionally renders no in-body greeting row: identity comes
/// from the [ShellTabScaffold] title and the attention stage leads the brief
/// — the same contract as the Wealth hub.
const Widget _kNoGreetingHeader = SizedBox.shrink();

/// Finance planning workspace.
///
/// The surface is deliberately action-first: due and risky work is promoted,
/// ongoing plans stay visible, and calculators remain secondary.
class PlanHubPage extends ConsumerWidget {
  const PlanHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(planningHubStatusProvider);
    final fire = ref.watch(fireDashboardViewProvider);
    final attentionItems = _attentionItems(context, status);
    final showNextAction =
        attentionItems.isNotEmpty || status.isLoading || status.hasError;

    return ShellTabScaffold(
      title: l10n.planHubTitle,
      childPad: false,
      child: ShellTabPause(
        routePath: FinanceRoutes.plan,
        placeholder: const SizedBox.expand(),
        // Shared brief skeleton (same as Health Today / Wealth hub). The
        // attention section is the visual anchor; when nothing needs
        // attention the stage collapses and the plan sections lead.
        //
        // Width capping stays on the outer AdaptiveContentFrame (as before):
        // BriefScaffold.maxContentWidth would wrap the whole brief in one
        // eager Column child, breaking the lazy ListView row building.
        child: AdaptiveContentFrame(
          maxWidth: AdaptiveMaxWidth.dashboard,
          expandSinglePrimary: true,
          padding: EdgeInsets.zero,
          primary: BriefScaffold(
            padding: shellTabContentPadding(context, top: AppSpacing.s8),
            onRefresh: () => _refreshPlanningWorkspace(ref),
            greeting: _kNoGreetingHeader,
            stage: showNextAction
                ? _NextActionSection(status: status, items: attentionItems)
                : const SizedBox.shrink(),
            summaryTiles: _planningSummaryTiles(context, l10n, status, fire),
          ),
        ),
      ),
    );
  }
}

Future<void> _refreshPlanningWorkspace(WidgetRef ref) async {
  final now = DateTime.now();
  final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  ref
    ..invalidate(dashboardSnapshotProvider)
    ..invalidate(fireDashboardViewProvider)
    ..invalidate(moneyRunwayProvider)
    ..invalidate(financialDecisionsProvider)
    ..invalidate(activeRebalanceExecutionProvider)
    ..invalidate(rebalancePortfolioSnapshotProvider)
    ..invalidate(monthlyBudgetSummaryProvider(month))
    ..invalidate(dcaPlansProvider)
    ..invalidate(wheelLifecyclesProvider)
    ..invalidate(planningHubStatusProvider);
  try {
    await Future.wait<Object?>([
      ref.read(dashboardSnapshotProvider.future),
      ref.read(financialDecisionsProvider.future),
      ref.read(activeRebalanceExecutionProvider.future),
      ref.read(rebalancePortfolioSnapshotProvider.future),
      ref.read(dcaPlansProvider.future),
    ]);
  } catch (_) {
    // Individual source failures are rendered as a partial-status notice.
  }
}

/// Ordered overview tiles for the brief grid: outlook, active plans, review
/// history, then the secondary "add plan" entry point.
List<AdaptiveSummaryTile> _planningSummaryTiles(
  BuildContext context,
  AppLocalizations l10n,
  PlanningHubStatus status,
  AsyncValue<FireDashboardView> fire,
) {
  final formatters = AppFormatters(locale: Localizations.localeOf(context));
  final outlook = <_PlanEntrySpec>[
    _runwayEntry(l10n, status),
    _budgetEntry(l10n, status),
    _fireEntry(l10n, formatters, fire),
  ];
  final investments = <_PlanEntrySpec>[
    _dcaEntry(context, l10n, status),
    _rebalanceEntry(l10n, status),
    if (!kIsWeb) _incomeStrategyEntry(l10n, status),
  ];
  final reviews = <_PlanEntrySpec>[_lifeEventsEntry(l10n, status)];

  return [
    AdaptiveSummaryTile(
      role: AdaptiveSummaryTileRole.supporting,
      child: _PlanSection(
        key: const ValueKey('plan-outlook-section'),
        title: l10n.planOverviewTitle,
        entries: outlook,
      ),
    ),
    AdaptiveSummaryTile(
      role: AdaptiveSummaryTileRole.featured,
      child: _PlanSection(
        key: const ValueKey('plan-investments-section'),
        title: l10n.planMyPlansTitle,
        entries: investments,
      ),
    ),
    AdaptiveSummaryTile(
      role: AdaptiveSummaryTileRole.continuous,
      child: _PlanSection(
        key: const ValueKey('plan-reviews-section'),
        title: l10n.lifeEventDecisionHistory,
        entries: reviews,
      ),
    ),
    const AdaptiveSummaryTile(
      role: AdaptiveSummaryTileRole.continuous,
      child: _PlanAddPlanMenu(),
    ),
  ];
}

class _NextActionSection extends StatefulWidget {
  const _NextActionSection({required this.status, required this.items});

  final PlanningHubStatus status;
  final List<_PlanEntrySpec> items;

  @override
  State<_NextActionSection> createState() => _NextActionSectionState();
}

class _NextActionSectionState extends State<_NextActionSection> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _NextActionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length <= 1 && _expanded) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final next = widget.items.firstOrNull;
    final hasAttention = widget.items.isNotEmpty;
    final tone = next?.tone ?? AppBadgeTone.neutral;
    final visibleItems = _expanded
        ? widget.items
        : widget.items.take(1).toList(growable: false);

    return AppSection.group(
      title: l10n.planAttentionTitle,
      trailing: hasAttention || widget.status.isLoading
          ? AppBadge(
              label: widget.status.isLoading && !hasAttention
                  ? l10n.commonLoading
                  : l10n.planAttentionCount(widget.items.length),
              size: AppBadgeSize.compact,
              tone: widget.status.isLoading && !hasAttention
                  ? AppBadgeTone.neutral
                  : tone,
              icon: hasAttention ? next!.icon : FLucideIcons.loaderCircle,
            )
          : null,
      children: [
        if (hasAttention) ...[
          for (final (index, item) in visibleItems.indexed) ...[
            if (index > 0) const FDivider(),
            _AttentionRow(spec: item),
          ],
          if (widget.items.length > 1) ...[
            const SizedBox(height: AppSpacing.s6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FButton(
                variant: FButtonVariant.ghost,
                onPress: () => setState(() => _expanded = !_expanded),
                prefix: Icon(
                  _expanded ? FLucideIcons.chevronUp : FLucideIcons.listChecks,
                  size: AppIconSizes.sm,
                ),
                child: Text(
                  _expanded
                      ? l10n.planAttentionCollapse
                      : l10n.planAttentionShowAll(widget.items.length - 1),
                ),
              ),
            ),
          ],
        ] else if (widget.status.isLoading)
          const _AttentionSkeleton(),
        if (widget.status.hasError) ...[
          if (hasAttention || widget.status.isLoading)
            const SizedBox(height: AppSpacing.s10),
          Row(
            children: [
              Icon(
                FLucideIcons.cloudAlert,
                size: AppIconSizes.sm,
                color: context.appTheme.status.warning.fg,
              ),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  l10n.planStatusPartiallyUnavailable,
                  style: context.captionStyle,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.spec});

  final _PlanEntrySpec spec;

  @override
  Widget build(BuildContext context) {
    return AppNavRow(
      icon: spec.icon,
      title: spec.title,
      subtitle: spec.subtitle,
      tone: spec.tone,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      onTap: () => context.push(spec.path),
    );
  }
}

class _AttentionSkeleton extends StatelessWidget {
  const _AttentionSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SkeletonBox(width: 36, height: 36, radius: AppRadius.sm),
        SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s6),
              SkeletonBox(width: 220, height: 12, radius: AppRadius.sm),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({super.key, required this.title, required this.entries});

  final String title;
  final List<_PlanEntrySpec> entries;

  @override
  Widget build(BuildContext context) {
    return AppSection.group(
      title: title,
      children: [
        for (final (index, entry) in entries.indexed) ...[
          if (index > 0) const FDivider(),
          _PlanRow(spec: entry),
        ],
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.spec});

  final _PlanEntrySpec spec;

  @override
  Widget build(BuildContext context) {
    final needsAttention =
        spec.tone == AppBadgeTone.warning || spec.tone == AppBadgeTone.error;
    return AppNavRow(
      icon: spec.icon,
      title: spec.title,
      subtitle: spec.subtitle,
      tone: needsAttention ? spec.tone : null,
      titleMaxLines: 2,
      subtitleMaxLines: 2,
      trailing: needsAttention
          ? AppBadge(
              label: spec.badge ?? _toneLabel(context, spec.tone),
              tone: spec.tone,
              size: AppBadgeSize.compact,
            )
          : null,
      onTap: () => context.push(spec.path),
    );
  }
}

/// Secondary entry point: calculators and plan creation stay one tap away
/// without competing with the status-driven sections above.
class _PlanAddPlanMenu extends StatelessWidget {
  const _PlanAddPlanMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppAdaptiveActionMenu(
      title: l10n.planAddPlanAction,
      actions: [
        AppAdaptiveAction(
          icon: FLucideIcons.piggyBank,
          title: l10n.planBudgetSectionTitle,
          onPress: () => context.push(FinanceRoutes.planBudget),
        ),
        AppAdaptiveAction(
          icon: FLucideIcons.scale,
          title: l10n.planRebalanceSectionTitle,
          onPress: () => context.push(FinanceRoutes.planRebalance),
        ),
        AppAdaptiveAction(
          icon: FLucideIcons.calendarClock,
          title: l10n.planDcaPlanTitle,
          onPress: () => context.push(FinanceRoutes.planDca),
        ),
        if (!kIsWeb)
          AppAdaptiveAction(
            icon: FLucideIcons.candlestickChart,
            title: l10n.incomeStrategyTitle,
            onPress: () => context.push(FinanceRoutes.planIncome),
          ),
        AppAdaptiveAction(
          icon: FLucideIcons.waypoints,
          title: l10n.lifeEventScenariosTitle,
          onPress: () => context.push(FinanceRoutes.planLifeEvents),
        ),
      ],
      triggerBuilder: (context, openMenu, focusNode) => Focus(
        focusNode: focusNode,
        child: Semantics(
          button: true,
          label: l10n.planAddPlanAction,
          child: AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: AppTappable(
              onPress: openMenu,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s16,
                  vertical: AppSpacing.s12,
                ),
                child: Row(
                  children: [
                    Icon(
                      FLucideIcons.layoutGrid,
                      size: AppIconSizes.sm,
                      color: context.theme.colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: Text(
                        l10n.planAddPlanAction,
                        style: context.labelStyle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Icon(
                      FLucideIcons.chevronRight,
                      size: AppIconSizes.sm,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
