import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/data/dashboard_insights_provider.dart';
import '../../home/domain/insight_models.dart';
import '../../home/ui/insight_feed_strings.dart';

/// Horizontal rail of "next action" cards rendered between the AI
/// context summary and the chat conversation.
///
/// Reuses [dashboardInsightsProvider] (the same source the home
/// AiInsightFeed renders vertically) so a recommendation only needs
/// to be authored once. Each card is tappable; tapping deep-links
/// into the relevant detail flow (FIRE, Rebalance, Expense report).
class AiActionCardsRail extends ConsumerWidget {
  const AiActionCardsRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(dashboardInsightsProvider);
    if (insights.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Text(
              l10n.aiActionCardsTitle,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: insights.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  _ActionCard(item: insights[i], l10n: l10n),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.item, required this.l10n});

  final InsightItem item;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final tint = item.iconColor ?? colors.primary;
    final route = item.route;
    return SizedBox(
      width: 240,
      child: SoftCard(
        onPress: route == null ? null : () => context.push(route),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(item.icon, size: 14, color: tint),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    insightHeadline(l10n, item),
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                insightDetail(l10n, item),
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                  height: 1.4,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (route != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.aiActionCardsOpen,
                  style: context.theme.typography.xs.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
