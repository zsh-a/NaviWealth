import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/data/auth_controller.dart';
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
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
              // IA contract §1: Settings is global meta — accessed from
              // the Today header avatar, not a tab. Pushes outside the
              // shell so pop returns to whatever tab the user came from.
              // Avatar replaces the previous gear so the editorial header
              // doesn't read as chrome-heavy; it can later carry a sync
              // status ring + an initial once display-name lands.
              const _AccountAvatarButton(),
            ],
          ),
          if (statusFragments.isNotEmpty) ...[
            const SizedBox(height: 6),
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

/// 36dp circular avatar in the top-right of the Today header. Single
/// entry point to /settings on mobile (the desktop shell pins Settings
/// at the bottom of its sidebar instead).
///
/// Two visual states:
///   * **logged-in / local-only**: teal-tinted disc with a person glyph
///     (initial-letter rendering will land once display name is in
///     [AuthSession]; keep the path open by reading auth state).
///   * **logged-out**: shouldn't render on Today — the auth guard
///     redirects to /login first — but if it does, the same disc shows
///     so the layout doesn't jump.
class _AccountAvatarButton extends ConsumerWidget {
  const _AccountAvatarButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    // Watch auth state so future profile-aware rendering can branch
    // without another refactor. Today the icon is the same either way.
    ref.watch(authControllerProvider);
    return Semantics(
      label: l10n.navSettingsTooltip,
      button: true,
      child: Tooltip(
        message: l10n.navSettingsTooltip,
        child: FTappable(
          onPress: () => context.push(AppRoutes.settings),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Soft primary tint — matches the avatar disc used in
              // settings (pre-Phase-D) and other "personal" affordances
              // so this reads as identity, not chrome.
              color: colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_outline,
              size: 18,
              color: colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
