/// Task heading and actions for the domain home.
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

    return ShellPageHeading(
      title: l10n.knowledgeInboxTitle,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.knowledgeCaptureAction,
          iconColor: DomainAccents.knowledge.resolve(
            context.appTheme.brightness,
          ),
          onPress: () => showKnowledgeCaptureSheet(context),
          order: -10,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.circleCheck,
          label: l10n.knowledgeNewDecision,
          onPress: () => showKnowledgeDecisionCapturePage(context),
          order: 10,
        ),
      ],
    );
  }
}
