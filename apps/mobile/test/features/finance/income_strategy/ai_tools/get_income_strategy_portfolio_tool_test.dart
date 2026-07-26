import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/income_strategy/ai_tools/get_income_strategy_portfolio_tool.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';

Future<T> _withRef<T>(
  ProviderContainer container,
  Future<T> Function(Ref ref) body,
) {
  final probe = FutureProvider<T>((ref) => body(ref));
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

void main() {
  test('returns the same composable snapshot with evidence', () async {
    final snapshot = PortfolioIncomeStrategySnapshot(
      baseCurrency: 'USD',
      unassignedCashFlows: const [],
      underlyings: [
        UnderlyingIncomeStrategySnapshot(
          asset: const IncomeStrategyAsset(
            assetId: 'us_stock:AAPL',
            symbol: 'AAPL',
            market: 'us_stock',
            currency: 'USD',
          ),
          enabledSleeves: const {
            IncomeStrategySleeveKind.dividends,
            IncomeStrategySleeveKind.leapsCall,
          },
          capitalBudget: Decimal.fromInt(5000),
          annualIncomeTarget: Decimal.fromInt(300),
          sleeves: {
            IncomeStrategySleeveKind.dividends: IncomeStrategySleeveSnapshot(
              kind: IncomeStrategySleeveKind.dividends,
              status: 'holding',
              realizedResult: Decimal.fromInt(42),
              projectedCash: Decimal.fromInt(12),
              capitalAtRisk: Decimal.fromInt(4000),
              marketValue: Decimal.fromInt(4000),
              deltaEquivalentShares: null,
              risks: const [],
              cashFlows: [
                IncomeStrategyCashFlow(
                  id: 'dividend:e1',
                  assetId: 'us_stock:AAPL',
                  sleeve: IncomeStrategySleeveKind.dividends,
                  kind: IncomeStrategyCashFlowKind.dividend,
                  state: IncomeStrategyCashFlowState.actual,
                  date: DateTime.utc(2026, 7, 1),
                  amount: Decimal.fromInt(42),
                  currency: 'USD',
                  sourceTable: 'dividend_events',
                  sourceId: 'e1',
                  hasCompleteEvidence: true,
                ),
              ],
            ),
          },
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

    const tool = GetIncomeStrategyPortfolioTool();
    final output = await _withRef(container, (ref) async {
      return await tool.invoke(
            DeviceToolContext(
              ref: ref,
              session: DeviceSession(messages: const <AnthropicChatMessage>[]),
            ),
            const <String, Object?>{'asset_id': 'us_stock:AAPL'},
          )
          as Map<String, Object?>;
    });
    final underlyings = output['underlyings']! as List<Object?>;
    final underlying = (underlyings.single as Map).cast<String, Object?>();

    expect(output['realized_result'], '42');
    expect(underlying['capital_budget'], '5000');
    expect(underlying['annual_income_target'], '300');
    expect(output['evidence'], isNotEmpty);
  });
}
