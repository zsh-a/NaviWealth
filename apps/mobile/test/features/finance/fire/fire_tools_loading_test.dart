import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/fire/ai_tools/get_fire_plan_tool.dart';
import 'package:naviwealth/features/finance/fire/ai_tools/get_fire_state_tool.dart';
import 'package:naviwealth/features/finance/fire/ai_tools/get_fire_stress_tests_tool.dart';
import 'package:naviwealth/features/finance/fire/ai_tools/propose_fire_plan_update_tool.dart';
import 'package:naviwealth/features/finance/fire/ai_tools/simulate_fire_plan_tool.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';

void main() {
  test('a settled absent plan is unconfigured data, not unavailable', () async {
    final container = ProviderContainer(
      overrides: [
        persistedFirePlanProvider.overrideWith((_) => Stream.value(null)),
        dashboardBaseCurrencyProvider.overrideWithValue('USD'),
      ],
    );
    addTearDown(container.dispose);
    final invoke = FutureProvider(
      (ref) => DriftDeviceToolDispatcher(
        ref: ref,
        registry: DeviceToolRegistry([const GetFirePlanTool()]),
      ).dispatch(const DeviceToolSession(), 'get_fire_plan', {}),
    );
    final result = await container.read(invoke.future) as Map;
    expect(result['is_configured'], isFalse);
    expect(result.containsKey('error'), isFalse);
  });

  for (final tool in <DeviceTool>[
    const GetFirePlanTool(),
    const GetFireStateTool(),
    const GetFireStressTestsTool(),
    const ProposeFirePlanUpdateTool(),
    const SimulateFirePlanTool(),
  ]) {
    for (final failure in [false, true]) {
      test(
        '${tool.name} waits for cold plan and propagates error=$failure',
        () async {
          final plans = StreamController<FirePlan?>();
          addTearDown(plans.close);
          final container = ProviderContainer(
            overrides: [
              persistedFirePlanProvider.overrideWith((_) => plans.stream),
              dashboardBaseCurrencyProvider.overrideWithValue('USD'),
              dashboardSnapshotProvider.overrideWith(
                (_) async => DashboardSnapshot.empty(
                  asOf: DateTime.now(),
                  baseCurrency: 'USD',
                ),
              ),
              cashFlowSummaryProvider.overrideWith(
                (_, request) async => CashFlowSummary(
                  period: request.period,
                  baseCurrency: 'USD',
                  buckets: const [],
                  totalInBase: Money.zero('USD'),
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          final invoke = FutureProvider(
            (ref) =>
                DriftDeviceToolDispatcher(
                  ref: ref,
                  registry: DeviceToolRegistry([tool]),
                ).dispatch(
                  const DeviceToolSession(),
                  tool.name,
                  tool is ProposeFirePlanUpdateTool
                      ? {'monthly_expenses': 2000}
                      : {},
                ),
          );
          var completed = false;
          final result = container.read(invoke.future).then((v) {
            completed = true;
            return v;
          });
          await container.pump();
          expect(completed, isFalse);
          if (failure) {
            plans.addError(StateError('plan_read_failed'));
            expect((await result as Map)['code'], 'tool_error');
          } else {
            plans.add(
              FirePlan.unset(baseCurrency: 'USD').copyWith(
                monthlyExpenses: Decimal.fromInt(1000),
                targetNetWorth: Decimal.fromInt(1000000),
              ),
            );
            final output = await result as Map;
            expect(output.containsKey('error'), isFalse);
            if (tool is GetFirePlanTool) {
              expect(output['monthly_expenses'], '1000');
            }
            if (tool is GetFireStateTool) {
              expect(output['safety_level'], isNot('unconfigured'));
            }
          }
        },
      );
    }
  }

  test(
    'unresolved projection uses dispatcher timeout and closes subscriptions',
    () async {
      final container = ProviderContainer(
        overrides: [
          persistedFirePlanProvider.overrideWith(
            (_) => const Stream<FirePlan?>.empty(),
          ),
          dashboardBaseCurrencyProvider.overrideWithValue('USD'),
        ],
      );
      addTearDown(container.dispose);
      final invoke = FutureProvider(
        (ref) => DriftDeviceToolDispatcher(
          ref: ref,
          registry: DeviceToolRegistry([const GetFirePlanTool()]),
          perToolTimeout: const Duration(milliseconds: 20),
        ).dispatch(const DeviceToolSession(), 'get_fire_plan', {}),
      );
      expect(
        (await container.read(invoke.future) as Map)['code'],
        'tool_timeout',
      );
      await container.pump();
      expect(container.exists(persistedFirePlanProvider), isFalse);
    },
  );
}
