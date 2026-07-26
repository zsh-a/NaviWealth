import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/ai_tools/get_income_strategy_portfolio_tool.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';

void main() {
  test('returns normalized YTD metrics with source evidence', () async {
    final asOf = DateTime.utc(2026, 7, 26);
    final metric = IncomeStrategyMoneyMetric(
      value: Money(Decimal.fromInt(42), 'USD'),
    );
    final sleeve = IncomeStrategySleeveSnapshot(
      kind: IncomeStrategySleeveKind.dividends,
      status: 'holding',
      periodStart: DateTime.utc(2026),
      asOf: asOf,
      realizedIncome: metric,
      realizedResult: metric,
      projectedCash: IncomeStrategyMoneyMetric.zero('USD'),
      exposure: IncomeStrategyExposure(
        capitalAtRisk: IncomeStrategyMoneyMetric.zero('USD'),
      ),
      cashFlows: [
        IncomeStrategyCashFlow(
          id: 'dividend:e1',
          assetId: 'nasdaq:AAPL',
          sleeve: IncomeStrategySleeveKind.dividends,
          kind: IncomeStrategyCashFlowKind.dividend,
          state: IncomeStrategyCashFlowState.actual,
          date: DateTime.utc(2026, 7, 1),
          amount: Money(Decimal.fromInt(42), 'USD'),
          baseAmount: Money(Decimal.fromInt(42), 'USD'),
          source: const IncomeStrategySourceRef(
            table: 'dividend_events',
            id: 'e1',
          ),
        ),
      ],
      risks: const [],
    );
    final snapshot = PortfolioIncomeStrategySnapshot(
      baseCurrency: 'USD',
      periodStart: DateTime.utc(2026),
      asOf: asOf,
      unassignedCashFlows: const [],
      underlyings: [
        UnderlyingIncomeStrategySnapshot(
          asset: const IncomeStrategyAsset(
            assetId: 'nasdaq:AAPL',
            symbol: 'AAPL',
            market: 'nasdaq',
            currency: 'USD',
          ),
          baseCurrency: 'USD',
          periodStart: DateTime.utc(2026),
          asOf: asOf,
          enabledSleeves: {IncomeStrategySleeveKind.dividends},
          capitalBudget: Money(Decimal.fromInt(5000), 'USD'),
          annualIncomeTarget: Money(Decimal.fromInt(300), 'USD'),
          sleeves: {IncomeStrategySleeveKind.dividends: sleeve},
          risks: const [],
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        portfolioIncomeStrategyProvider.overrideWith((ref) async => snapshot),
      ],
    );
    addTearDown(container.dispose);
    late Map<String, Object?> output;
    final probe = FutureProvider<void>((ref) async {
      output =
          await const GetIncomeStrategyPortfolioTool().invoke(
                DeviceToolContext(
                  ref: ref,
                  session: DeviceSession(
                    messages: const <AnthropicChatMessage>[],
                  ),
                ),
                const <String, Object?>{'asset_id': 'nasdaq:AAPL'},
              )
              as Map<String, Object?>;
    });
    container.listen(probe, (_, _) {});
    await container.read(probe.future);

    expect(output['realized_result_ytd'], '42');
    expect(output['period_start'], DateTime.utc(2026).toIso8601String());
    expect(output['evidence'], isNotEmpty);
  });
}
