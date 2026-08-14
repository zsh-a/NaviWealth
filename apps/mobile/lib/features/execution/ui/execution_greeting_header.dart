/// Editorial identity row for the ExecutionOS Today brief.
///
/// Replaces the static "Today" page title with a personalized greeting +
/// a concise briefing subtitle, matching the FinanceOS Today cockpit
/// (`home_greeting_header.dart`). The overview strip below owns the
/// counts and filters; this row stays a stable page identity and hosts
/// the headerless shell chrome ([ShellActionRow]) plus the Review entry
/// that previously lived in the `FHeader`.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';

class ExecutionGreetingHeader extends StatelessWidget {
  const ExecutionGreetingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s8,
        AppSpacing.s20,
        AppSpacing.s16,
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
                  _greeting(l10n, DateTime.now().hour),
                  style: context.briefGreetingTitleStyle,
                ),
              ),
              AppIconButton(
                icon: FLucideIcons.history,
                tooltip: l10n.executionReviewTitle,
                onPress: () => context.push(ExecutionRoutes.review),
              ),
              // Headerless Today root: the greeting row is where the
              // cross-domain shell chrome lands (domain switch + global
              // Search / Settings). Hidden on desktop, where the dock /
              // sidebar own these.
              const ShellActionRow(),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(l10n.executionTodayBriefSubtitle, style: context.captionStyle),
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
