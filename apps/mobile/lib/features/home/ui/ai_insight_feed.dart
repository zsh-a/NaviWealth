import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/intent/intent.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ai_object_capsule.dart';
import '../data/dashboard_insights_provider.dart';
import '../data/dismissed_insights_store.dart';
import '../domain/insight_models.dart';
import 'home_section.dart';
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
    return HomeSection(
      title: l10n.dashboardAiInsightsTitle,
      child: StaggeredColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < insights.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == insights.length - 1 ? 0 : AppSpacing.s8,
              ),
              child: _InsightCard(item: insights[i]),
            ),
        ],
      ),
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
    final summary = Row(
      children: [
        SizedBox(
          width: AppSpacing.s32,
          height: AppSpacing.s32,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Icon(
              item.icon,
              size: AppIconSizes.md,
              color: iconTint.withValues(alpha: AppOpacity.prominent),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                insightHeadline(l10n, item),
                style: context.labelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                insightDetail(l10n, item),
                style: context.captionStyle,
                maxLines: _expanded ? null : 2,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (tappable) ...[
          const SizedBox(width: AppSpacing.s8),
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.h18,
            color: colors.mutedForeground.withValues(
              alpha: AppOpacity.prominent,
            ),
          ),
        ],
      ],
    );

    return HomeSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tappable)
            FTappable(
              onPress: item.onTap ?? () => context.push(route!),
              child: summary,
            )
          else
            summary,
          const SizedBox(height: AppSpacing.s10),
          _InsightInlineActions(
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
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.s8),
            Container(
              width: double.infinity,
              height: 1,
              color: colors.foreground.withValues(alpha: AppOpacity.faint),
            ),
          ],
        ],
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

/// Inline action cluster. Keeping the actions in normal layout makes them
/// discoverable on touch screens and avoids a second hidden interaction model.
class _InsightInlineActions extends StatelessWidget {
  const _InsightInlineActions({
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
    return Wrap(
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s6,
      crossAxisAlignment: WrapCrossAlignment.center,
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
    return AppIconButton(
      icon: icon,
      tooltip: tooltip,
      onPress: onTap,
      size: 28,
      iconSize: AppIconSizes.xs,
      iconColor: context.theme.colors.mutedForeground,
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
