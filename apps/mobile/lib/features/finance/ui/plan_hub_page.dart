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
/// while goals and investment strategies stay visible as stable entry points.
class PlanHubPage extends ConsumerWidget {
  const PlanHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(planningHubStatusProvider);
    final fire = ref.watch(fireDashboardViewProvider);
    final entries = _planningEntries(context, l10n, status, fire);
    final attentionItems =
        entries
            .where((entry) => entry.requiresAttention)
            .toList(growable: false)
          ..sort((a, b) => a.priority.compareTo(b.priority));
    final showAttention =
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
            stage: showAttention
                ? _AttentionSection(status: status, items: attentionItems)
                : const SizedBox.shrink(),
            summaryTiles: _planningSummaryTiles(l10n, entries),
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

/// Ordered overview tiles for the brief grid: near-term cash safety, long-term
/// goals, and investment actions.
List<AdaptiveSummaryTile> _planningSummaryTiles(
  AppLocalizations l10n,
  List<_PlanEntrySpec> entries,
) {
  final cashSafety = entries
      .where((entry) => entry.group == _PlanEntryGroup.cashSafety)
      .toList(growable: false);
  final longTermGoals = entries
      .where((entry) => entry.group == _PlanEntryGroup.longTermGoals)
      .toList(growable: false);
  final investmentPlan = entries
      .where((entry) => entry.group == _PlanEntryGroup.investmentPlan)
      .toList(growable: false);
  return [
    AdaptiveSummaryTile(
      role: AdaptiveSummaryTileRole.featured,
      child: _PlanSection(
        key: const ValueKey('plan-cash-safety-section'),
        title: l10n.planCashSafetyTitle,
        entries: cashSafety,
      ),
    ),
    AdaptiveSummaryTile(
      role: AdaptiveSummaryTileRole.standard,
      child: _PlanSection(
        key: const ValueKey('plan-long-term-goals-section'),
        title: l10n.planLongTermGoalsTitle,
        entries: longTermGoals,
      ),
    ),
    AdaptiveSummaryTile(
      role: AdaptiveSummaryTileRole.standard,
      child: _CollapsiblePlanSection(
        key: const ValueKey('plan-investment-plan-section'),
        title: l10n.planInvestmentPlanTitle,
        entries: investmentPlan,
      ),
    ),
  ];
}

class _AttentionSection extends StatefulWidget {
  const _AttentionSection({required this.status, required this.items});

  final PlanningHubStatus status;
  final List<_PlanEntrySpec> items;

  @override
  State<_AttentionSection> createState() => _AttentionSectionState();
}

class _AttentionSectionState extends State<_AttentionSection> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _AttentionSection oldWidget) {
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

class _CollapsiblePlanSection extends StatefulWidget {
  const _CollapsiblePlanSection({
    super.key,
    required this.title,
    required this.entries,
  });

  final String title;
  final List<_PlanEntrySpec> entries;

  @override
  State<_CollapsiblePlanSection> createState() =>
      _CollapsiblePlanSectionState();
}

class _CollapsiblePlanSectionState extends State<_CollapsiblePlanSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSection.group(
      title: widget.title,
      children: [
        Semantics(
          expanded: _expanded,
          child: AppNavRow(
            key: const ValueKey('plan-investment-tools-disclosure'),
            icon: FLucideIcons.layers,
            title: l10n.planInvestmentToolsTitle,
            subtitle: l10n.planInvestmentToolsSummary,
            titleMaxLines: 2,
            subtitleMaxLines: 2,
            showChevron: false,
            trailing: Icon(
              _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
              size: AppIconSizes.sm,
              color: context.theme.colors.mutedForeground,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded)
          for (final entry in widget.entries) ...[
            const FDivider(),
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
    return AppNavRow(
      icon: spec.icon,
      title: spec.title,
      subtitle: spec.requiresAttention ? null : spec.subtitle,
      titleMaxLines: 2,
      subtitleMaxLines: 2,
      onTap: () => context.push(spec.path),
    );
  }
}
