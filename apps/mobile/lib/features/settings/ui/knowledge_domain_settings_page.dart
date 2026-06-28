/// KnowledgeOS domain detail settings.
///
/// Shows KnowledgeOS-specific navigation. Reached from the Settings
/// overview's KnowledgeOS row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'inline_setting_row.dart';
import 'settings_page_frame.dart';

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
                  onTap: () => context.goNamed(AppRouteNames.knowledgeInbox),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.library,
                  label: 'KnowledgeOS · Library',
                  subtitle: l10n.settingsDomainsKnowledgeLibrarySubtitle,
                  onTap: () => context.goNamed(AppRouteNames.knowledgeLibrary),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.clipboardCheck,
                  label: 'KnowledgeOS · Review',
                  subtitle: l10n.settingsDomainsKnowledgeReviewSubtitle,
                  onTap: () => context.goNamed(AppRouteNames.knowledgeReview),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.brainCircuit,
                  label: l10n.settingsDomainsKnowledgeMemoryTitle,
                  subtitle: l10n.settingsDomainsKnowledgeMemorySubtitle,
                  onTap: () => context.goNamed(AppRouteNames.aiModels),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
