/// ExecutionOS domain detail settings.
///
/// Shows ExecutionOS-specific navigation. Reached through
/// `/settings/domains/execution`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../execution/composition/execution_route_paths.dart';
import 'inline_setting_row.dart';
import 'settings_page_frame.dart';

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
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              children: [
                InlineLinkRow(
                  icon: FLucideIcons.listTodo,
                  label: 'ExecutionOS · Today',
                  subtitle: l10n.settingsDomainsExecutionTodaySubtitle,
                  onTap: () => context.goNamed(ExecutionRouteNames.today),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.handshake,
                  label: 'ExecutionOS · Commitments',
                  subtitle: l10n.executionCommandCommitments,
                  onTap: () => context.goNamed(ExecutionRouteNames.commitments),
                ),
                const AppGradientDivider(),
                InlineLinkRow(
                  icon: FLucideIcons.clipboardCheck,
                  label: 'ExecutionOS · Review',
                  subtitle: l10n.executionCommandReview,
                  onTap: () => context.goNamed(ExecutionRouteNames.review),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
