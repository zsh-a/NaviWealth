import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

/// Plan tab — umbrella page showing FIRE progress, portfolio analytics,
/// and rebalance overview as summary cards.
class PlanPage extends ConsumerWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: GlassAppBar(title: Text(l10n.navPlan)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = !Breakpoints.isMobile(constraints.maxWidth);
          final padding = isWide ? Spacing.pageWide : Spacing.pageMobile;

          final cards = <Widget>[
            _PlanCard(
              icon: Icons.flag_outlined,
              title: l10n.planFireTitle,
              subtitle: l10n.planFireSubtitle,
              onTap: () => context.push(AppRoutes.planFire),
            ),
            _PlanCard(
              icon: Icons.pie_chart_outline,
              title: l10n.planAnalyticsTitle,
              subtitle: l10n.planAnalyticsSubtitle,
              onTap: () => context.push(AppRoutes.planAnalytics),
            ),
            _PlanCard(
              icon: Icons.balance_outlined,
              title: l10n.planRebalanceTitle,
              subtitle: l10n.planRebalanceSubtitle,
              onTap: () => context.push(AppRoutes.planRebalance),
            ),
          ];

          if (isWide) {
            return ListView(
              padding: padding,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: Spacing.s16),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: Spacing.s16),
                cards[2],
              ],
            );
          }

          return ListView(
            padding: padding.copyWith(
              bottom:
                  padding.bottom +
                  Spacing.floatingBarClearance +
                  MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: Spacing.s12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LiquidGlassCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: Spacing.card,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: Radii.brMd,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: theme.colorScheme.primary, size: 22),
            ),
            const SizedBox(width: Spacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: Spacing.s4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
