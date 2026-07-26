import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';

import '../application/income_strategy_asset_resolver.dart';
import '../application/income_strategy_rules.dart';
import '../application/wheel_strategy_view.dart';
import '../composition/income_strategy_modules.dart';
import '../domain/income_strategy.dart';
import '../domain/income_strategy_assembler.dart';
import 'income_strategy_plan_providers.dart';

export 'income_strategy_plan_providers.dart';

final incomeStrategyModulesProvider = Provider<List<IncomeStrategyModule>>(
  (ref) => kIncomeStrategyModules,
);

final incomeStrategyNowProvider = Provider<DateTime>(
  (ref) => DateTime.now().toUtc(),
);

final portfolioIncomeStrategyProvider =
    FutureProvider.autoDispose<PortfolioIncomeStrategySnapshot>((ref) async {
      final baseCurrency = ref.watch(baseCurrencyProvider).toUpperCase();
      final converter = ref.watch(cashFlowCurrencyConverterProvider);
      final modules = ref.watch(incomeStrategyModulesProvider);
      final asOf = ref.watch(incomeStrategyNowProvider).toUtc();
      final assetsFuture = ref.watch(allAssetsStreamProvider.future);
      final plansFuture = ref.watch(incomeStrategyPlansProvider.future);
      final assetList = await assetsFuture;
      final plans = await plansFuture;
      final resolver = IncomeStrategyAssetResolver(assetList);
      final context = IncomeStrategyModuleContext(
        baseCurrency: baseCurrency,
        asOf: asOf,
        converter: converter,
        assets: resolver,
        plans: plans,
      );
      final results = await Future.wait([
        for (final module in modules) module.load(ref, context),
      ]);
      return const IncomeStrategyAssembler().assemble(
        baseCurrency: baseCurrency,
        asOf: asOf,
        converter: converter,
        plans: plans,
        contributions: [for (final result in results) ...result.contributions],
        unassignedCashFlows: [
          for (final result in results) ...result.unassignedCashFlows,
        ],
        rules: [
          ...kCoreIncomeStrategyRules,
          for (final module in modules) ...module.rules,
        ],
      );
    });

final wheelStrategyViewsProvider =
    Provider.autoDispose<AsyncValue<List<WheelStrategyView>>>((ref) {
      return ref
          .watch(portfolioIncomeStrategyProvider)
          .whenData(buildWheelStrategyViews);
    });
