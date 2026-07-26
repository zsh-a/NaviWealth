import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/domain_enums.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_cash_projection.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';

import '../application/dividend_income_sleeve_adapter.dart';
import '../application/income_strategy_asset_resolver.dart';
import '../application/leaps_income_sleeve_adapter.dart';
import '../application/wheel_income_sleeve_adapter.dart';
import '../application/wheel_strategy_view.dart';
import '../domain/income_strategy.dart';
import '../domain/income_strategy_assembler.dart';
import '../domain/income_strategy_plan.dart';
import 'income_strategy_plan_repository.dart';

final incomeStrategyPlanRepositoryProvider =
    FutureProvider<IncomeStrategyPlanRepository>((ref) async {
      return IncomeStrategyPlanRepository(
        db: await ref.watch(appDatabaseProvider.future),
        outbox: await ref.watch(outboxStoreProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

final incomeStrategyPlansProvider =
    StreamProvider.autoDispose<List<IncomeStrategyPlan>>((ref) async* {
      final repository = await ref.watch(
        incomeStrategyPlanRepositoryProvider.future,
      );
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repository.watchActive(ownerUserId);
    });

final portfolioIncomeStrategyProvider =
    FutureProvider.autoDispose<PortfolioIncomeStrategySnapshot>((ref) async {
      final centerFuture = ref.watch(dividendCenterSnapshotProvider.future);
      final holdingsFuture = ref.watch(holdingsSnapshotProvider.future);
      final projectedDividendsFuture = ref.watch(
        dividendCashProjection90dProvider.future,
      );
      final assetsFuture = ref.watch(allAssetsStreamProvider.future);
      final plansFuture = ref.watch(incomeStrategyPlansProvider.future);
      final journalFuture = ref.watch(tradeJournalEntriesProvider.future);
      final leapsFuture = ref.watch(leapsCallPositionsProvider.future);

      final center = await centerFuture;
      final holdings = await holdingsFuture;
      final projectedDividends = await projectedDividendsFuture;
      final assetList = await assetsFuture;
      final resolver = IncomeStrategyAssetResolver(assetList);
      final plans = await plansFuture;
      final journal = await journalFuture;
      final leaps = await leapsFuture;

      return const IncomeStrategyAssembler().assemble(
        baseCurrency: center.baseCurrency,
        plans: plans,
        unassignedCashFlows: [
          for (var i = 0; i < projectedDividends.length; i++)
            _projectedDividendFlow(
              projectedDividends[i],
              index: i,
              currency: center.baseCurrency,
            ),
        ],
        contributions: [
          ...const DividendIncomeSleeveAdapter().build(
            center: center,
            holdings: {
              for (final entry in holdings.entries)
                if (assetList.any(
                  (asset) =>
                      asset.id == entry.key &&
                      kSecuritiesAssetTypes.contains(asset.type),
                ))
                  entry.key: entry.value,
            },
            assets: resolver,
          ),
          ...const WheelIncomeSleeveAdapter().buildFromEntries(
            entries: journal,
            assets: resolver,
          ),
          ...const LeapsIncomeSleeveAdapter().build(
            positions: leaps,
            assets: resolver,
          ),
        ],
      );
    });

final wheelStrategyViewsProvider =
    Provider.autoDispose<AsyncValue<List<WheelStrategyView>>>((ref) {
      return ref
          .watch(portfolioIncomeStrategyProvider)
          .whenData(buildWheelStrategyViews);
    });

IncomeStrategyCashFlow _projectedDividendFlow(
  DividendCashProjection projection, {
  required int index,
  required String currency,
}) => IncomeStrategyCashFlow(
  id: 'dividend_projection:${projection.date.toIso8601String()}:$index',
  assetId: 'portfolio',
  sleeve: IncomeStrategySleeveKind.dividends,
  kind: IncomeStrategyCashFlowKind.dividend,
  state: projection.certainty == DividendCashCertainty.declared
      ? IncomeStrategyCashFlowState.declared
      : IncomeStrategyCashFlowState.estimated,
  date: projection.date,
  amount: projection.netAmount,
  currency: currency,
  sourceTable: 'dividend_forecast',
  sourceId: projection.date.toIso8601String(),
  hasCompleteEvidence: projection.hasTaxEvidence,
);
