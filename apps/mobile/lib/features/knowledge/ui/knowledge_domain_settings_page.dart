/// KnowledgeOS domain detail settings.
///
/// Shows KnowledgeOS-specific navigation. Reached from the Settings
/// overview's KnowledgeOS row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/settings_route_paths.dart';
import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '_widgets.dart';

class KnowledgeDomainSettingsPage extends ConsumerWidget {
  const KnowledgeDomainSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return AppPageScaffold(
      title: 'KnowledgeOS',
      childPad: false,
      child: SettingsPageFrame(
        children: [
          KnowledgeSection(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            children: [
              InlineLinkRow(
                icon: FLucideIcons.brainCircuit,
                label: l10n.settingsDomainsKnowledgeMemoryTitle,
                subtitle: l10n.settingsDomainsKnowledgeMemorySubtitle,
                onTap: () => context.goNamed(SettingsRouteNames.aiModels),
              ),
              const AppGradientDivider(),
              InlineLinkRow(
                icon: FLucideIcons.bot,
                label: l10n.agentSettingsTitle,
                subtitle: l10n.agentSettingsSubtitle,
                onTap: () => context.goNamed(SettingsRouteNames.agents),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
