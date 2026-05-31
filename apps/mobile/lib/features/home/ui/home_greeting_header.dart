import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design_system/design_system.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/dashboard_insights_provider.dart';
import '../data/dashboard_providers.dart';

/// Wealth-status hero rendered above the Net Worth card.
///
/// Replaces the static "Overview" page title with a personalized
/// greeting + a one-line "this is where you stand" status. The goal is
/// to make the home page feel like a long-term wealth cockpit (Apple
/// Stocks / Arc-style) rather than a generic dashboard with a chrome
/// title.
///
/// Status line composes:
///   • Net worth direction (MTD %)
///   • Number of available AI insights
///
/// Both lines are silent when the data is missing — the header
/// gracefully degrades to just the greeting.
class HomeGreetingHeader extends ConsumerWidget {
  const HomeGreetingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hour = DateTime.now().hour;
    final greeting = _greeting(l10n, hour);

    final metricsAsync = ref.watch(dashboardHeaderMetricsProvider);
    final insights = ref.watch(dashboardInsightsProvider);
    final pct = metricsAsync.value?.monthlyChangePct;
    final colors = context.theme.colors;

    final statusFragments = <_StatusFragment>[];
    if (pct != null && pct.isFinite) {
      final direction = pct >= 0 ? '+' : '−';
      final absPct = (pct.abs() * 100).toStringAsFixed(1);
      final color = pct >= 0
          ? colors.primary
          : colors.foreground.withValues(alpha: 0.85);
      statusFragments.add(
        _StatusFragment(
          text: l10n.homeGreetingNetWorthFragment('$direction$absPct%'),
          color: color,
        ),
      );
    }
    if (insights.isNotEmpty) {
      statusFragments.add(
        _StatusFragment(
          text: l10n.homeGreetingInsightsFragment(insights.length),
          color: colors.mutedForeground,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s20, AppSpacing.s8, AppSpacing.s20, AppSpacing.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  greeting,
                  style: context.theme.typography.xl.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
              // Today has no `FHeader`, so the editorial greeting row is
              // where the cross-domain shell chrome lands (domain switch +
              // global Search / Settings) — the same cluster the headered
              // tabs render via `ShellTabScaffold`. Hidden on desktop,
              // where the dock / sidebar own these.
              const ShellActionRow(),
            ],
          ),
          if (statusFragments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s6),
            DefaultTextStyle.merge(
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
                height: 1.35,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  for (var i = 0; i < statusFragments.length; i++) ...[
                    Text(
                      statusFragments[i].text,
                      style: TextStyle(
                        color: statusFragments[i].color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (i < statusFragments.length - 1)
                      Text(
                        '·',
                        style: TextStyle(
                          color: colors.mutedForeground.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _greeting(AppLocalizations l10n, int hour) {
    if (hour < 5) return l10n.homeGreetingNight;
    if (hour < 12) return l10n.homeGreetingMorning;
    if (hour < 18) return l10n.homeGreetingAfternoon;
    return l10n.homeGreetingEvening;
  }
}

class _StatusFragment {
  const _StatusFragment({required this.text, required this.color});
  final String text;
  final Color color;
}
