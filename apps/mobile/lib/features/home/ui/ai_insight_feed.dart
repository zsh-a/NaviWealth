import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/intent/intent.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ai_hover_overlay.dart';
import '../../ai_chat/ui/ai_object_capsule.dart';
import '../data/dashboard_insights_provider.dart';
import '../data/dismissed_insights_store.dart';
import '../domain/insight_models.dart';
import 'insight_feed_strings.dart';

/// Vertical feed of AI-generated insights — the calm-finance replacement
/// for the legacy horizontal `InsightStrip` chip carousel.
///
/// Each insight renders as a full-width [SoftCard] with:
///  - left: rounded tinted icon disc (color reflects severity)
///  - middle: headline + detail copy
///  - right: chevron when the card is tappable
///
/// The whole card is tappable (no separate "View" button) — consistent
/// with iOS-style list rows where the row is the action target.
class AiInsightFeed extends StatelessWidget {
  const AiInsightFeed({super.key, required this.insights});

  final List<InsightItem> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: AppSpacing.s4),
          child: Text(
            l10n.dashboardAiInsightsTitle,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
        for (var i = 0; i < insights.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == insights.length - 1 ? 0 : 8),
            child: _StaggeredFadeIn(
              delay: Duration(milliseconds: 60 * i),
              child: _InsightCard(item: insights[i]),
            ),
          ),
      ],
    );
  }
}

/// §5.10.1 Layer 3 — three-action insight card.
///
/// Each card now exposes:
///   * 展开 — toggles an inline detail block (kept tiny; the deep-link
///     route is still on the row tap as the "primary" affordance).
///   * 问一下 — fires the existing explain_insight capsule, which
///     opens the inline AI bottom sheet pre-loaded with insight
///     context.
///   * 忽略 — records a dismissal in [DismissedInsightsStore]; the
///     card disappears immediately (the provider re-emits without
///     it on the next tick).
class _InsightCard extends ConsumerStatefulWidget {
  const _InsightCard({required this.item});

  final InsightItem item;

  @override
  ConsumerState<_InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends ConsumerState<_InsightCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final route = item.route;
    final tappable = item.onTap != null || route != null;
    final sem = SemanticColors.of(context);
    final iconTint = switch (item.tone) {
      InsightTone.success => sem.success,
      InsightTone.warning => sem.warning,
      InsightTone.danger => sem.danger,
      InsightTone.info => sem.info,
      null => colors.primary,
    };
    return AiHoverOverlay(
      capsule: _InsightOverlayActions(
        expanded: _expanded,
        onExpand: () => setState(() => _expanded = !_expanded),
        onDismiss: _dismiss,
        askCapsule: AiObjectCapsule(
          source: 'home_insight_card',
          intent: 'explain_insight',
          object: AiObjectRef(type: 'insight', id: _insightStableId(item)),
          objectLabel: insightHeadline(l10n, item),
          fallbackLabel: l10n.dashboardInsightActionAsk,
        ),
        l10n: l10n,
      ),
      child: SoftCard(
        onPress: !tappable ? null : (item.onTap ?? () => context.push(route!)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconTint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(item.icon, size: AppIconSizes.h18, color: iconTint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        insightHeadline(l10n, item),
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        insightDetail(l10n, item),
                        style: context.theme.typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (tappable) ...[
                  const SizedBox(width: 8),
                  Icon(
                    FLucideIcons.chevronRight,
                    size: AppIconSizes.h18,
                    color: colors.mutedForeground.withValues(alpha: 0.6),
                  ),
                ],
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: AppSpacing.s8),
              _ExpandedDetail(item: item),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _dismiss() async {
    final store = ref.read(dismissedInsightsStoreProvider);
    await store.dismiss(
      DismissedInsightKey(
        kind: widget.item.kind,
        scopeHash: insightScopeHash(widget.item),
      ),
    );
  }
}

class _ExpandedDetail extends StatelessWidget {
  const _ExpandedDetail({required this.item});
  final InsightItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s10),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        _expandedDetailFor(item),
        style: context.theme.typography.xs.copyWith(color: colors.foreground),
      ),
    );
  }

  static String _expandedDetailFor(InsightItem item) {
    // Kind-specific extra context. Kept ASCII-light and English to
    // avoid an ARB explosion for what is effectively a debug-style
    // breadcrumb; the user-facing summary is on the headline + detail
    // rows above.
    switch (item.kind) {
      case InsightKind.duplicateCharge:
        return 'Pairs detected within ±2 days, after refund + recurring '
            'exclusion. Tap the row to open the matching transactions.';
      case InsightKind.monthlySummary:
        return 'Computed from the dashboard trend: difference between '
            'the latest reading inside the prior month and the latest '
            'reading before it.';
      case InsightKind.fireProgress:
      case InsightKind.fireReached:
        return 'From the FIRE planner baseline scenario.';
      case InsightKind.portfolioDrift:
        return 'Allocation drift exceeds the configured threshold.';
      case InsightKind.maturity:
        return 'Deposit matures within the alert window.';
      case InsightKind.anomaly:
        return 'Projected month-end spend vs. the last 3 months.';
      case InsightKind.ingestQueue:
        return 'Parsed transactions awaiting confirmation. Tap to '
            'review, confirm, or skip duplicates before they post.';
      case InsightKind.cashFlowDeficit:
        return 'Current-month inflow minus outflow is below zero, computed '
            'from the shared cashflow summary used by the Home cards.';
      case InsightKind.fireOsHighWithdrawalRate:
        return 'Trailing 12-month annual spend / investable assets is '
            "above the plan's safe-withdrawal rate. Open the FIRE OS "
            'hero card for the breakdown.';
      case InsightKind.fireOsLowCashBucket:
        return 'Liquid cash divided by monthly expense is below the '
            "plan's target cash-bucket months. Top-up suggested on the "
            'FIRE OS hero card.';
      case InsightKind.fireOsUnmappedHoldings:
        return 'These holdings are real estate, vehicles, or other '
            'assets the allocator left out by default. Map them on the '
            'FIRE OS buckets card if they should fund the plan.';
      case InsightKind.fireOsBucketDeviation:
        return 'A non-cash bucket has drifted past 10% off its target. '
            'Open the FIRE OS buckets card for the breakdown — or '
            'rebalance / propose a rule change.';
    }
  }
}

/// Floating action cluster that the hover overlay reveals in the
/// card's top-right corner. Groups expand / ask-AI / dismiss into one
/// tinted chip so the underlying card stays text-only at rest.
class _InsightOverlayActions extends StatelessWidget {
  const _InsightOverlayActions({
    required this.expanded,
    required this.onExpand,
    required this.onDismiss,
    required this.askCapsule,
    required this.l10n,
  });

  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onDismiss;
  final Widget askCapsule;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4, vertical: AppSpacing.s2),
        decoration: BoxDecoration(
          color: isDark
              ? colors.background.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: colors.foreground.withValues(alpha: isDark ? 0.10 : 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OverlayIconButton(
              icon: expanded
                  ? FLucideIcons.foldVertical
                  : FLucideIcons.unfoldVertical,
              tooltip: l10n.dashboardInsightActionExpand,
              onTap: onExpand,
            ),
            askCapsule,
            _OverlayIconButton(
              icon: FLucideIcons.x,
              tooltip: l10n.dashboardInsightActionDismiss,
              onTap: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTooltip(
      tipBuilder: (_, _) => Text(tooltip),
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6, vertical: AppSpacing.s4),
          child: Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
        ),
      ),
    );
  }
}

/// Synthesise a stable insight id from kind + key params so
/// the AiTrace records `object_id` consistently across rebuilds. Not a
/// persistent identifier — purely for attribution in this session.
String _insightStableId(InsightItem item) {
  return [
    item.kind.name,
    item.category?.name ?? '',
    item.monthsToTarget?.toString() ?? '',
    item.driftPct?.toStringAsFixed(2) ?? '',
    item.maturityCount?.toString() ?? '',
    item.anomalyPct?.toStringAsFixed(2) ?? '',
  ].where((s) => s.isNotEmpty).join('|');
}

/// Tiny entrance animation: 6dp upward translate + opacity 0 → 1 over
/// 240ms, gated by [delay] so a list of cards stagger in.
class _StaggeredFadeIn extends StatefulWidget {
  const _StaggeredFadeIn({required this.child, required this.delay});

  final Widget child;
  final Duration delay;

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
