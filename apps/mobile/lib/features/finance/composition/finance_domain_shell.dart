/// FinanceOS `DomainShellSpec` registration (`docs/architecture/lifeos-shell.md`
/// §3, D-1.8).
///
/// FinanceOS is the seed domain, so this spec is always present and
/// captures the 4-tab IA (Today / Activity / Wealth / Plan). Optional
/// domains such as HealthOS, KnowledgeOS, and ExecutionOS register their own
/// specs; bootstrap merges active specs through [activeDomainShellsProvider].
library;

import 'package:forui/forui.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/domain_shell.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'finance_route_paths.dart';

/// Stable branch order for FinanceOS' stateful tab shell.
///
/// In-domain shortcuts should switch stateful branches instead of issuing a
/// top-level route change. This keeps the adaptive tab chrome mounted while
/// moving between tab roots.
enum FinanceShellTab { today, activity, wealth, plan }

DomainShellSpec financeDomainShell(AppLocalizations l10n) {
  return DomainShellSpec(
    scope: DomainScope.finance,
    label: l10n.lifeDomainFinance,
    icon: FLucideIcons.wallet,
    selectedIcon: FLucideIcons.wallet,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: FLucideIcons.layoutDashboard,
        selectedIcon: FLucideIcons.layoutDashboard,
        label: l10n.navToday,
        routePath: FinanceRoutes.home,
      ),
      DomainShellTab(
        icon: FLucideIcons.receipt,
        selectedIcon: FLucideIcons.receipt,
        label: l10n.navActivity,
        routePath: FinanceRoutes.activity,
      ),
      DomainShellTab(
        icon: FLucideIcons.wallet,
        selectedIcon: FLucideIcons.wallet,
        label: l10n.navWealth,
        routePath: FinanceRoutes.wealth,
      ),
      DomainShellTab(
        icon: FLucideIcons.lightbulb,
        selectedIcon: FLucideIcons.lightbulb,
        label: l10n.navPlan,
        routePath: FinanceRoutes.plan,
      ),
    ],
  );
}
