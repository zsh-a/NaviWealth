/// Editorial identity row for the KnowledgeOS Inbox brief.
///
/// Replaces the static "Inbox" page title with a personalized greeting +
/// a concise briefing subtitle, matching the FinanceOS / HealthOS /
/// ExecutionOS Today cockpits (`home_greeting_header.dart`). The due-review
/// stage below owns the actionable content; this row stays a stable page
/// identity and hosts the headerless shell chrome ([ShellActionRow]) plus
/// the capture action that previously lived in the shell tab header.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'knowledge_capture_sheet.dart';

class KnowledgeGreetingHeader extends StatelessWidget {
  const KnowledgeGreetingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      // No horizontal inset: `BriefLazyListScaffold` already applies the
      // page padding, so an inner one would push the greeting past the
      // cards' left edge.
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
                child: Text(
                  _greeting(l10n, DateTime.now().hour),
                  style: context.briefGreetingTitleStyle,
                ),
              ),
              AppIconButton(
                icon: FLucideIcons.plus,
                tooltip: l10n.knowledgeCaptureAction,
                // Domain identity accent (KnowledgeOS indigo) on the inbox's
                // one primary action.
                iconColor: DomainAccents.knowledge.resolve(
                  context.appTheme.brightness,
                ),
                onPress: () => showKnowledgeCaptureSheet(context),
              ),
              // Headerless inbox root: the greeting row is where the
              // cross-domain shell chrome lands (domain switch + global
              // Search / Settings). Hidden on desktop, where the dock /
              // sidebar own these.
              const ShellActionRow(),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(l10n.knowledgeInboxTitle, style: context.captionStyle),
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
