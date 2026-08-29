/// HealthOS `DomainShellSpec` — Today + Trends after Plan merge.
library;

import 'package:forui/forui.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/domain_shell.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'health_route_paths.dart';

/// Build the HealthOS shell spec (2 tabs: Today / Trends).
DomainShellSpec healthDomainShell(AppLocalizations l10n) {
  return DomainShellSpec(
    scope: DomainScope.health,
    label: l10n.lifeDomainHealth,
    icon: FLucideIcons.heart,
    selectedIcon: FLucideIcons.heart,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: FLucideIcons.sun,
        selectedIcon: FLucideIcons.sun,
        label: l10n.healthTabToday,
        routePath: HealthRoutes.today,
      ),
      DomainShellTab(
        icon: FLucideIcons.trendingUp,
        selectedIcon: FLucideIcons.trendingUp,
        label: l10n.healthTabTrend,
        routePath: HealthRoutes.trend,
      ),
    ],
  );
}
