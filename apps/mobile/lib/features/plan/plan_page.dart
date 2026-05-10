import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'ui/plan_overview.dart';

/// Plan tab: umbrella page for FIRE progress, portfolio analytics,
/// and rebalance overview.
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      header: FHeader.nested(title: Text(l10n.navPlan)),
      childPad: false,
      child: const Material(
          color: Colors.transparent,
          child: PlanOverview(),
        ),
    );
  }
}
