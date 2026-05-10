import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import 'ui/plan_overview.dart';

/// Plan tab: umbrella page for FIRE progress, portfolio analytics,
/// and rebalance overview.
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l10n.navPlan),
      ),
      body: const PlanOverview(),
    );
  }
}
