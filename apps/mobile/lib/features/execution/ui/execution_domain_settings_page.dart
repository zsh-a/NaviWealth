/// ExecutionOS domain detail settings.
///
/// Shows ExecutionOS-specific navigation. Reached through
/// `/settings/domains/execution`.
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

class ExecutionDomainSettingsPage extends ConsumerWidget {
  const ExecutionDomainSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return AppPageScaffold(
      title: 'ExecutionOS',
      childPad: false,
      child: SettingsPageFrame(
        children: [
          SoftCard.raised(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                InlineLinkRow(
                  icon: FLucideIcons.bot,
                  label: l10n.agentSettingsTitle,
                  subtitle: l10n.agentSettingsSubtitle,
                  onTap: () => context.goNamed(SettingsRouteNames.agents),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
