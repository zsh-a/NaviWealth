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
import '../composition/knowledge_route_paths.dart';

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
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                InlineLinkRow(
                  icon: FLucideIcons.inbox,
                  label: 'KnowledgeOS · Inbox',
                  subtitle: l10n.settingsDomainsKnowledgeInboxSubtitle,
                  onTap: () => context.goNamed(KnowledgeRouteNames.inbox),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.library,
                  label: 'KnowledgeOS · Library',
                  subtitle: l10n.settingsDomainsKnowledgeLibrarySubtitle,
                  onTap: () => context.goNamed(KnowledgeRouteNames.library),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.clipboardCheck,
                  label: 'KnowledgeOS · Review',
                  subtitle: l10n.settingsDomainsKnowledgeReviewSubtitle,
                  onTap: () => context.goNamed(KnowledgeRouteNames.review),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.brainCircuit,
                  label: l10n.settingsDomainsKnowledgeMemoryTitle,
                  subtitle: l10n.settingsDomainsKnowledgeMemorySubtitle,
                  onTap: () => context.goNamed(SettingsRouteNames.aiModels),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
