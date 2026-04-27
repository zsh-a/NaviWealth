import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.assetsAppBarTitle)),
      body: Center(child: Text(l10n.assetsEmptyHint)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: null,
        icon: const Icon(Icons.add),
        label: Text(l10n.assetsAddAction),
      ),
    );
  }
}
