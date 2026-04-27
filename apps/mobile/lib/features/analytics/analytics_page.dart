import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analyticsAppBarTitle)),
      body: const Center(child: Text('FIR-7 / FIR-8')),
    );
  }
}
