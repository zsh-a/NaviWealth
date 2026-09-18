import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/analytics/data/providers.dart';
import 'package:naviwealth/features/finance/analytics/data/risk_threshold_preferences.dart';
import 'package:naviwealth/features/finance/analytics/domain/concentration_risk.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 1, 1);
final _sync = SyncMeta(
  ownerUserId: 'owner',
  updatedAt: _now,
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

class _Holdings implements HoldingService {
  final snapshots = {
    for (final entry in {'A': 100, 'B': 400}.entries)
      entry.key: HoldingSnapshot(
        assetId: entry.key,
        quantity: Decimal.fromInt(10),
        costBasisInAssetCurrency: Decimal.fromInt(entry.value),
        marketValueInAssetCurrency: Decimal.fromInt(entry.value),
        assetCurrency: 'USD',
        costBasisInBase: Decimal.fromInt(entry.value),
        marketValueInBase: Decimal.fromInt(entry.value),
        unrealizedPnlInBase: Decimal.zero,
        weight: (Decimal.fromInt(entry.value) / Decimal.fromInt(500))
            .toDecimal(),
        baseCurrency: 'USD',
        asOf: _now,
      ),
  };

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      snapshots;

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => [
    for (final id in snapshots.keys)
      Lot(
        id: 'lot-$id',
        openingTransactionId: 'tx-$id',
        accountId: 'broker',
        assetId: id,
        currency: 'USD',
        originalQuantity: Decimal.fromInt(10),
        remainingQuantity: Decimal.fromInt(10),
        costPerUnit: Decimal.fromInt(id == 'A' ? 10 : 40),
        openedAt: _now,
      ),
  ];

  @override
  Future<void> invalidateFrom(DateTime from) async {}

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) =>
      throw UnimplementedError();
}

void main() {
  test('risk follows partial assignments, empty and unassigned scopes without changing global risk', () async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.risk.threshold.asset': 0.6,
    });
    final prefs = await SharedPreferences.getInstance();
    final holdings = _Holdings();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        holdingsSnapshotProvider.overrideWith((_) async => holdings.snapshots),
        holdingServiceProvider.overrideWith((_) async => holdings),
        equityAssetsStreamProvider.overrideWith(
          (_) => Stream.value([
            for (final id in ['A', 'B'])
              Asset(
                id: id,
                type: AssetType.stock,
                symbol: id,
                currency: 'USD',
                sync: _sync,
              ),
          ]),
        ),
        investmentPortfoliosProvider.overrideWith(
          (_) => Stream.value([
            for (final id in ['selected', 'empty'])
              InvestmentPortfolio(
                id: id,
                name: id,
                baseCurrency: 'USD',
                goalId: null,
                color: null,
                createdAt: _now,
                archived: false,
                sync: _sync,
              ),
          ]),
        ),
        portfolioCapitalAssignmentsProvider.overrideWith(
          (_) => Stream.value([
            PortfolioCapitalAssignment(
              id: 'half-A',
              portfolioId: 'selected',
              rebalanceGroupId: 'group',
              sourceKind: PortfolioCapitalSourceKind.lot,
              sourceId: 'lot-A',
              quantity: Decimal.fromInt(5),
              amount: null,
              currency: null,
              assignedAt: _now,
              sync: _sync,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      selectedPortfolioConcentrationAlertsProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    Future<List<ConcentrationAlert>> assetAlerts() async =>
        (await container.read(
          selectedPortfolioConcentrationAlertsProvider.future,
        )).where((alert) => alert.dimension == RiskDimension.asset).toList();

    expect((await assetAlerts()).single.label, 'B');
    container.read(selectedInvestmentPortfolioIdProvider.notifier).state =
        'selected';
    final selected = (await assetAlerts()).single;
    expect(selected.label, 'A');
    expect(selected.weight, 1);
    expect(selected.valueInBase, Decimal.fromInt(50));
    final global = await container.read(concentrationAlertsProvider.future);
    expect(
      global
          .where((alert) => alert.dimension == RiskDimension.asset)
          .single
          .label,
      'B',
    );

    container.read(selectedInvestmentPortfolioIdProvider.notifier).state =
        'empty';
    expect(
      await container.read(selectedPortfolioConcentrationAlertsProvider.future),
      isEmpty,
    );
    container.read(selectedInvestmentPortfolioIdProvider.notifier).state =
        kUnassignedInvestmentPortfolioId;
    expect((await assetAlerts()).single.label, 'B');
    container.read(selectedInvestmentPortfolioIdProvider.notifier).state = null;
    expect((await assetAlerts()).single.weight, 0.8);

    container.read(selectedInvestmentPortfolioIdProvider.notifier).state =
        'selected';
    await assetAlerts();
    await container
        .read(concentrationThresholdsProvider.notifier)
        .updateAsset(1);
    expect(await assetAlerts(), isEmpty);
  });
}
