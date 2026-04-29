import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.assetsAppBarTitle)),
      body: Center(child: Text(l10n.assetsEmptyHint)),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'assets-corp-action',
            onPressed: () => context.push('/assets/corporate-action'),
            icon: const Icon(Icons.account_tree_outlined),
            label: Text(l10n.assetsCorporateActionAction),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'assets-add',
            onPressed: null,
            icon: const Icon(Icons.add),
            label: Text(l10n.assetsAddAction),
          ),
        ],
      ),
    );
  }
}
