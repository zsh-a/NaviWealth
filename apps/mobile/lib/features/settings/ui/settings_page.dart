import 'package:flutter/widgets.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'overview/settings_overview.dart';
export 'overview/settings_overview.dart' show AppearanceSettingsPage;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.settingsAppBarTitle,
      childPad: false,
      child: const SettingsOverview(),
    );
  }
}
