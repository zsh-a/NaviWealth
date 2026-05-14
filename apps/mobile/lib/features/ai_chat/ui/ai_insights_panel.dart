import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// "Insights" section block — entry points into the deterministic
/// plan dashboards (FIRE / Rebalance / Analytics) that live under
/// `/accounts/...`. Designed to slot under the AI chat conversation
/// (now mounted at `/settings/ai-history`) as a collapsible section so
/// the user can jump to a dashboard without losing chat context.
class AiInsightsPanel extends StatefulWidget {
  const AiInsightsPanel({super.key});

  @override
  State<AiInsightsPanel> createState() => _AiInsightsPanelState();
}

class _AiInsightsPanelState extends State<AiInsightsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SoftCard(
        child: Column(
          children: [
            FTappable(
              onPress: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.aiInsightsPanelTitle,
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: colors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const FDivider(),
              _InsightLink(
                icon: Icons.flag_outlined,
                label: l10n.planFireTitle,
                route: AppRoutes.accountsFire,
              ),
              const FDivider(),
              _InsightLink(
                icon: Icons.tune_outlined,
                label: l10n.aiInsightsRebalanceTitle,
                route: AppRoutes.accountsRebalance,
              ),
              const FDivider(),
              _InsightLink(
                icon: Icons.pie_chart_outline,
                label: l10n.planAnalyticsTitle,
                route: AppRoutes.accountsAnalytics,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsightLink extends StatelessWidget {
  const _InsightLink({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: () => context.push(route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.mutedForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: context.theme.typography.sm,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: colors.mutedForeground.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
