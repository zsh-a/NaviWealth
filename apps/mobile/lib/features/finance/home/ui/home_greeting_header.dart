import 'package:flutter/widgets.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Editorial identity row for the FinanceOS Today brief.
///
/// Replaces the static "Overview" page title with a personalized
/// greeting + a concise briefing subtitle, keeping the page task-oriented
/// rather than presenting another generic dashboard title.
///
/// Financial metrics and agent results render in their own surfaces instead
/// of competing with this stable page identity row.
class HomeGreetingHeader extends StatelessWidget {
  const HomeGreetingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hour = DateTime.now().hour;
    final greeting = _greeting(l10n, hour);

    return Padding(
      // No horizontal inset: `BriefScaffold` already applies the page
      // padding, so an inner one would push the greeting past the cards'
      // left edge.
      padding: const EdgeInsets.only(
        top: AppSpacing.s8,
        bottom: AppSpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(greeting, style: context.briefGreetingTitleStyle),
              ),
              // Today has no `FHeader`, so the editorial greeting row is
              // where the cross-domain shell chrome lands (domain switch +
              // global Search / Settings) — the same cluster the headered
              // tabs render via `ShellTabScaffold`. Hidden on desktop,
              // where the dock / sidebar own these.
              const ShellActionRow(),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(l10n.homeTodayBriefSubtitle, style: context.captionStyle),
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
