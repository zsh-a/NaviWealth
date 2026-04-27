import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAppBarTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(l10n.settingsAccountTitle),
            subtitle: Text(l10n.settingsAccountSubtitle),
          ),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: Text(l10n.settingsBaseCurrencyTitle),
            subtitle: Text(l10n.settingsBaseCurrencySubtitle('CNY')),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsAboutTitle),
            subtitle: Text(l10n.settingsAboutSubtitle('0.1.0')),
          ),
        ],
      ),
    );
  }
}
