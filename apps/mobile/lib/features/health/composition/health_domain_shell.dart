/// HealthOS `DomainShellSpec` registration (`docs/lifeos-shell.md`
/// §3 + `docs/healthos-domain.md` §5, D-2.3).
///
/// Mirrors `features/finance_domain_shell.dart`. Tabs per HealthOS
/// IA contract: Today / Trend / Plan. Strings are literals for now —
/// l10n keys land in D-2.2 when the real pages ship, since dogfooders
/// see this surface in English / Chinese mixed prose either way.
library;

import 'package:flutter/material.dart';

import '../../../app/route_paths.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/domain_shell.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Build the HealthOS shell spec.
///
/// [l10n] is accepted for parity with `financeDomainShell(l10n)` and
/// to keep the call-site uniform; today it's unused (placeholder
/// labels). When D-2.2 ships and the UI is final, swap to localised
/// strings here without changing the bootstrap call.
DomainShellSpec healthDomainShell(AppLocalizations l10n) {
  return const DomainShellSpec(
    scope: DomainScope.health,
    label: 'HealthOS',
    icon: Icons.favorite_outline,
    selectedIcon: Icons.favorite,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: Icons.wb_sunny_outlined,
        selectedIcon: Icons.wb_sunny,
        label: 'Today',
        routePath: AppRoutes.healthToday,
      ),
      DomainShellTab(
        icon: Icons.show_chart_outlined,
        selectedIcon: Icons.show_chart,
        label: 'Trend',
        routePath: AppRoutes.healthTrend,
      ),
      DomainShellTab(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: 'Plan',
        routePath: AppRoutes.healthPlan,
      ),
    ],
  );
}
