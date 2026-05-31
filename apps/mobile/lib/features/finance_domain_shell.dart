/// FinanceOS `DomainShellSpec` registration (`docs/lifeos-shell.md`
/// §3, D-1.8).
///
/// FinanceOS is the seed domain, so this spec is always present and
/// captures the 4-tab IA (Today / Activity / Wealth / Plan). Optional
/// domains such as HealthOS and KnowledgeOS register their own specs;
/// bootstrap merges active specs through [activeDomainShellsProvider].
library;

import 'package:forui/forui.dart';

import '../app/route_paths.dart';
import '../core/auth/domain_scope.dart';
import '../core/shell/domain_shell.dart';
import '../l10n/gen/app_localizations.dart';

DomainShellSpec financeDomainShell(AppLocalizations l10n) {
  return DomainShellSpec(
    scope: DomainScope.finance,
    label: 'FinanceOS',
    icon: FLucideIcons.wallet,
    selectedIcon: FLucideIcons.wallet,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: FLucideIcons.layoutDashboard,
        selectedIcon: FLucideIcons.layoutDashboard,
        label: l10n.navToday,
        routePath: AppRoutes.home,
      ),
      DomainShellTab(
        icon: FLucideIcons.receipt,
        selectedIcon: FLucideIcons.receipt,
        label: l10n.navActivity,
        routePath: AppRoutes.activity,
      ),
      DomainShellTab(
        icon: FLucideIcons.wallet,
        selectedIcon: FLucideIcons.wallet,
        label: l10n.navWealth,
        routePath: AppRoutes.wealth,
      ),
      DomainShellTab(
        icon: FLucideIcons.lightbulb,
        selectedIcon: FLucideIcons.lightbulb,
        label: l10n.navPlan,
        routePath: AppRoutes.plan,
      ),
    ],
  );
}
