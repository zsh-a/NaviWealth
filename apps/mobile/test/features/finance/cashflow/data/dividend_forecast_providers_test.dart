import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';

void main() {
  test('computes resilience through the isolate-backed provider', () async {
    final container = ProviderContainer(
      overrides: [
        dividendCenterSnapshotProvider.overrideWith(
          (_) async => DividendCenterSnapshot(
            baseCurrency: 'USD',
            yearToDateGross: Decimal.zero,
            ttmGross: Decimal.zero,
            priorYearToDateGross: Decimal.zero,
            ttmWithholding: Decimal.zero,
            events: const [],
            ranking: const [],
            months: const [],
          ),
        ),
        dividendCenterNowProvider.overrideWithValue(DateTime.utc(2026, 7, 1)),
        dividendForecastDeclaredActionsProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(container.dispose);

    final report = await container.read(dividendResilienceProvider.future);

    expect(report.periodEnd, DateTime.utc(2026, 7, 1));
    expect(report.rolling, isEmpty);
  });

  test('normalizes declared foreign dividends into the portfolio currency', () {
    final converter = FxRateCurrencyConverter(
      InMemoryFxRateLookup([
        FxRate(
          base: 'USD',
          quote: 'CNY',
          date: DateTime.utc(2026, 7, 1),
          rate: Decimal.fromInt(7),
          source: 'test',
        ),
      ]),
    );

    final result = normalizeDeclaredDividendActions(
      actions: [
        CashDividendAction(
          id: 'declared-aapl',
          assetId: 'us:AAPL',
          effectiveDate: DateTime.utc(2026, 8, 1),
          transactionId: 'tx-aapl',
          accountId: 'broker',
          currency: 'USD',
          amountPerShare: Decimal.parse('1.5'),
          withholdingTax: Decimal.parse('0.3'),
        ),
      ],
      baseCurrency: 'CNY',
      converter: converter,
    );

    final action = result.actions.single as CashDividendAction;
    expect(action.currency, 'CNY');
    expect(action.amountPerShare, Decimal.parse('10.5'));
    expect(action.withholdingTax, Decimal.parse('2.1'));
    expect(result.excludedCurrencies, isEmpty);
  });

  test('reports declared currencies that have no FX rate', () {
    final result = normalizeDeclaredDividendActions(
      actions: [
        CashDividendAction(
          id: 'declared-aapl',
          assetId: 'us:AAPL',
          effectiveDate: DateTime.utc(2026, 8, 1),
          transactionId: 'tx-aapl',
          accountId: 'broker',
          currency: 'USD',
          amountPerShare: Decimal.one,
          withholdingTax: Decimal.zero,
        ),
      ],
      baseCurrency: 'CNY',
      converter: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
    );

    expect(result.actions, isEmpty);
    expect(result.excludedCurrencies, {'USD'});
  });
}
