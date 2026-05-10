import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import 'ui/settings_overview.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.settingsAppBarTitle),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: const SettingsOverview(),
    );
  }
}
