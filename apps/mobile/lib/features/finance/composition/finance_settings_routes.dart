import 'package:go_router/go_router.dart';

import '../../../core/lifeos/domain_pack.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../ui/settings/fire_stress_settings_page.dart';
import '../ui/settings/fx_rates_page.dart';
import '../ui/settings/monthly_expense_settings_page.dart';
import '../ui/settings/risk_thresholds_page.dart';

/// Top-level Settings routes owned by FinanceOS.
List<RouteBase> financeSettingsRoutes(DomainSettingsRouteWrapper wrap) {
  return [
    GoRoute(
      path: _settingsChildPath(SettingsRoutes.fxRates),
      name: SettingsRouteNames.fxRates,
      builder: (context, state) => wrap(const FxRatesPage()),
    ),
    GoRoute(
      path: _settingsChildPath(SettingsRoutes.riskThresholds),
      name: SettingsRouteNames.riskThresholds,
      builder: (context, state) => wrap(const RiskThresholdsPage()),
    ),
    GoRoute(
      path: _settingsChildPath(SettingsRoutes.stressTest),
      name: SettingsRouteNames.stressTest,
      builder: (context, state) => wrap(const FireStressSettingsPage()),
    ),
    GoRoute(
      path: _settingsChildPath(SettingsRoutes.monthlyExpense),
      name: SettingsRouteNames.monthlyExpense,
      builder: (context, state) => wrap(const MonthlyExpenseSettingsPage()),
    ),
  ];
}

String _settingsChildPath(String absolutePath) {
  const prefix = '${SettingsRoutes.root}/';
  if (!absolutePath.startsWith(prefix)) return absolutePath;
  return absolutePath.substring(prefix.length);
}
