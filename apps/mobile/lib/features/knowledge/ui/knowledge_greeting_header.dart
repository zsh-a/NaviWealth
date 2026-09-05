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

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.s8,
        bottom: AppSpacing.s16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              l10n.knowledgeInboxTitle,
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
          const ShellActionRow(),
        ],
      ),
    );
  }
}
