import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
///   • Number of visible FinanceOS agent results
///
/// Both lines are silent when the data is missing — the header
/// gracefully degrades to just the greeting.
class HomeGreetingHeader extends ConsumerWidget {
  const HomeGreetingHeader({this.agentArtifactCount = 0, super.key});

  final int agentArtifactCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hour = DateTime.now().hour;
    final greeting = _greeting(l10n, hour);

    final metricsAsync = ref.watch(dashboardHeaderMetricsProvider);
    final pct = metricsAsync.value?.monthlyChangePct;
    final colors = context.theme.colors;

    final statusFragments = <_StatusFragment>[];
    if (pct != null && pct.isFinite) {
      final direction = pct >= 0 ? '+' : '−';
      final absPct = (pct.abs() * 100).toStringAsFixed(1);
      final color = pct >= 0
          ? colors.primary
          : colors.foreground.withValues(alpha: AppOpacity.overlay);
      statusFragments.add(
        _StatusFragment(
          text: l10n.homeGreetingNetWorthFragment('$direction$absPct%'),
          color: color,
        ),
      );
    }
    if (agentArtifactCount > 0) {
      statusFragments.add(
        _StatusFragment(
          text: l10n.homeGreetingAgentResultsFragment(agentArtifactCount),
          color: colors.mutedForeground,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s8,
        AppSpacing.s20,
        AppSpacing.s14,
      ),
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
                  style: context.titleLabelStyle.copyWith(height: 1.1),
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
              style: context.bodyCaptionStyle.copyWith(height: 1.35),
              child: Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s2,
                children: [
                  for (var i = 0; i < statusFragments.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i > 0) ...[
                          Text(
                            '·',
                            style: context.bodyCaptionStyle.copyWith(
                              color: colors.mutedForeground.withValues(
                                alpha: AppOpacity.scrim,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                        ],
                        Text(
                          statusFragments[i].text,
                          style: context.mediumLabelStyle.copyWith(
                            color: statusFragments[i].color,
                          ),
                        ),
                      ],
                    ),
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
