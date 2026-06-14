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

class KnowledgeDomainSettingsPage extends ConsumerWidget {
  const KnowledgeDomainSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return AppPageScaffold(
      title: 'KnowledgeOS',
      childPad: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s16,
          AppSpacing.s16,
          AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                InlineLinkRow(
                  icon: FLucideIcons.inbox,
                  label: 'KnowledgeOS · Inbox',
                  subtitle: l10n.settingsDomainsKnowledgeInboxSubtitle,
                  onTap: () =>
                      context.goNamed(AppRouteNames.knowledgeInbox),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
