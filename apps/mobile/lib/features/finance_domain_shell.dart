/// FinanceOS `DomainShellSpec` registration (`docs/lifeos-shell.md`
/// §3, D-1.8).
///
/// FinanceOS is the seed domain, so this spec is always present and
/// captures the 4-tab IA (Today / Activity / Wealth / Plan). Optional
/// domains such as HealthOS and KnowledgeOS register their own specs;
/// bootstrap merges active specs through [activeDomainShellsProvider].
library;

import 'package:flutter/material.dart';

import '../app/route_paths.dart';
import '../core/auth/domain_scope.dart';
import '../core/shell/domain_shell.dart';
import '../l10n/gen/app_localizations.dart';

DomainShellSpec financeDomainShell(AppLocalizations l10n) {
  return DomainShellSpec(
    scope: DomainScope.finance,
    label: 'FinanceOS',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: l10n.navToday,
        routePath: AppRoutes.home,
      ),
      DomainShellTab(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: l10n.navActivity,
        routePath: AppRoutes.activity,
      ),
      DomainShellTab(
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet,
        label: l10n.navWealth,
        routePath: AppRoutes.wealth,
      ),
      DomainShellTab(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: l10n.navPlan,
        routePath: AppRoutes.plan,
      ),
    ],
  );
}
