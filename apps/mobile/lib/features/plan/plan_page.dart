import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
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
      appBar: GlassAppBar(title: Text(l10n.navPlan)),
      body: const PlanOverview(),
    );
  }
}
