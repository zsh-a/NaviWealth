import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.assetsAppBarTitle)),
      body: ListView(
        padding: Spacing.pageMobile,
        children: [
          Card(
            child: Padding(
              padding: Spacing.card,
              child: Text(l10n.assetsEmptyHint),
            ),
          ),
          const SizedBox(height: Spacing.s12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(l10n.assetsLiabilitiesLink),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/assets/liabilities'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: null,
        icon: const Icon(Icons.add),
        label: Text(l10n.assetsAddAction),
      ),
    );
  }
}
