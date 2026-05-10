import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../domain/insight_models.dart';
import 'insight_feed_strings.dart';

/// Vertical feed of AI-generated insights — the calm-finance replacement
/// for the legacy horizontal `InsightStrip` chip carousel.
///
/// Each insight renders as a full-width [FCard.raw] with:
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
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
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
            child: _InsightCard(item: insights[i]),
          ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.item});

  final InsightItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final route = item.route;
    final tappable = item.onTap != null || route != null;
    final iconTint = item.iconColor ?? colors.primary;
    return FCard.raw(
      child: FTappable(
        onPress: !tappable
            ? null
            : (item.onTap ?? () => context.push(route!)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconTint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(item.icon, size: 18, color: iconTint),
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
                    const SizedBox(height: 2),
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
                  Icons.chevron_right,
                  size: 18,
                  color: colors.mutedForeground.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
