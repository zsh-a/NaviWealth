import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'ui/settings_overview.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageScaffold(
      appBar: GlassAppBar(
        title: Text(l10n.settingsAppBarTitle),
        actions: const [],
      ),
      padding: EdgeInsets.zero,
      body: const SettingsOverview(),
    );
  }
}
