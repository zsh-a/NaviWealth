import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/settings_route_paths.dart';
import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Low-frequency diagnostics kept out of the everyday settings hierarchy.
class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.settingsAdvancedHubTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          AppSection.group(
            title: l10n.settingsAdvancedSection,
            children: [
              InlineLinkRow(
                icon: FLucideIcons.bug,
                label: l10n.settingsLogsTitle,
                subtitle: l10n.settingsLogsSubtitle,
                onTap: () => context.pushNamed(SettingsRouteNames.logs),
              ),
              const AppGradientDivider(),
              InlineLinkRow(
                icon: FLucideIcons.activity,
                label: l10n.settingsPerfTitle,
                subtitle: l10n.settingsPerfSubtitle,
                onTap: () => context.pushNamed(SettingsRouteNames.performance),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
