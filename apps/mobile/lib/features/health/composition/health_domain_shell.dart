/// HealthOS `DomainShellSpec` registration (`docs/architecture/lifeos-shell.md`
/// §3 + `docs/domains/healthos-domain.md` §5, D-2.3).
///
/// Mirrors `features/finance_domain_shell.dart`. Tabs per HealthOS
/// IA contract: Today / Trend / Plan. Labels come from l10n so the
/// shell stays consistent with the rest of the app chrome.
library;

import 'package:forui/forui.dart';

import '../../../app/route_paths.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/domain_shell.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Build the HealthOS shell spec.
///
/// [l10n] is accepted for parity with `financeDomainShell(l10n)` and
/// to keep the call-site uniform across domain specs.
DomainShellSpec healthDomainShell(AppLocalizations l10n) {
  return DomainShellSpec(
    scope: DomainScope.health,
    label: 'HealthOS',
    icon: FLucideIcons.heart,
    selectedIcon: FLucideIcons.heart,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: FLucideIcons.sun,
        selectedIcon: FLucideIcons.sun,
        label: l10n.healthTabToday,
        routePath: AppRoutes.healthToday,
      ),
      DomainShellTab(
        icon: FLucideIcons.trendingUp,
        selectedIcon: FLucideIcons.trendingUp,
        label: l10n.healthTabTrend,
        routePath: AppRoutes.healthTrend,
      ),
      DomainShellTab(
        icon: FLucideIcons.lightbulb,
        selectedIcon: FLucideIcons.lightbulb,
        label: l10n.healthTabPlan,
        routePath: AppRoutes.healthPlan,
      ),
    ],
  );
}
