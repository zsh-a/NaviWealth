import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'ui/settings_overview.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: appSubPageHeader(
        context: context,
        title: Text(l10n.settingsAppBarTitle),
      ),
      childPad: false,
      child: const SettingsOverview(),
    );
  }
}
