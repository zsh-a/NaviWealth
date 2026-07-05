// Flow / Task test: "Run portfolio analysis" — Task #7 in
// docs/development/testing-strategy.md.
//
// This boots the real app shell, discovers Holdings from the Wealth hub, and
// lands on the Portfolio analysis surface. The first-run state is intentional:
// it pins the allocation/positions report route before any investment holdings
// exist.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/portfolio_return.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/xirr_engine.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

class _EmptyHoldingService implements HoldingService {
  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      const {};

  @override
  Future<void> invalidateFrom(DateTime from) async {}

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) async =>
      LotInventorySnapshot(ownerUserId: 'flow', day: day, lots: const []);
}

class _EmptyPortfolioReturnService implements PortfolioReturnService {
  @override
  Future<PortfolioReturnResult> compute({
    required DateTime from,
    required DateTime to,
  }) async {
    return PortfolioReturnResult(
      from: from,
      to: to,
      baseCurrency: 'CNY',
      cashFlows: const [],
      solution: const XirrFallbackAbsolute(
        absoluteReturn: null,
        reason: 'too-few-flows',
      ),
    );
  }
}

void main() {
  group('Task: Run portfolio analysis', () {
    testWidgets('user opens Portfolio from Wealth holdings', (tester) async {
      await bootApp(
        tester,
        extraOverrides: [
          holdingServiceProvider.overrideWith(
            (ref) async => _EmptyHoldingService(),
          ),
          portfolioReturnServiceProvider.overrideWith(
            (ref) async => _EmptyPortfolioReturnService(),
          ),
          realizedPnlProvider.overrideWith((ref) async => const []),
          dividendForecast12mProvider.overrideWith(
            (ref) async => ProjectedDividend.empty(
              assetId: 'portfolio',
              currency: 'CNY',
              strategy: 'composite',
              confidence: DividendForecastConfidence.low,
            ),
          ),
          dividendCenterSnapshotProvider.overrideWith(
            (ref) async => DividendCenterSnapshot(
              baseCurrency: 'CNY',
              yearToDateGross: Decimal.zero,
              ttmGross: Decimal.zero,
              priorYearToDateGross: Decimal.zero,
              ttmWithholding: Decimal.zero,
              events: const [],
              ranking: const [],
              months: const [],
            ),
          ),
          dividendForecastDeclaredActionsProvider.overrideWith(
            (ref) => const <CorporateAction>[],
          ),
        ],
      );

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Wealth');

      final wealth = WealthPage(tester);
      await wealth.openPortfolio();
      await settle(tester);

      PortfolioAnalysisPageObject(tester).expectEmptyAnalysis();
      await closeApp(tester);
    }, tags: 'flow');
  });
}
