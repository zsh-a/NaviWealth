import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/features/cashflow/data/recurring_transaction_providers.dart';
import 'package:naviwealth/features/finance/ai_tools/drift_query_plan_executor.dart';
import 'package:naviwealth/features/finance/command_palette/finance_query_plan_executor_provider.dart';
import 'package:naviwealth/features/finance/composition/finance_bootstrap.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_providers.dart';

void main() {
  test('Finance composition wires query plans to the Drift executor', () {
    final container = ProviderContainer(
      overrides: financeCompositionOverrides(),
    );
    addTearDown(container.dispose);

    expect(
      container.read(financeQueryPlanExecutorProvider),
      isA<DriftQueryPlanExecutor>(),
    );
  });

  test('finance background starts price sync for local-only auth', () {
    var priceSyncStarted = 0;
    final recurringRuns = <DateTime>[];
    final container = ProviderContainer(
      overrides: [
        auth.authStateProvider.overrideWithValue(const AuthLocalOnly()),
        priceSyncCoordinatorBootstrapProvider.overrideWith((ref) {
          priceSyncStarted++;
        }),
        recurringMaterialiseDueProvider.overrideWith((ref, now) async {
          recurringRuns.add(now);
          return 0;
        }),
      ],
    );
    addTearDown(container.dispose);
    final bootstrapProvider = Provider<void>(financeBackgroundBootstrap);

    container.read(bootstrapProvider);

    expect(priceSyncStarted, 1);
    expect(recurringRuns, hasLength(1));
  });

  test('finance background skips price sync while logged out', () {
    var priceSyncStarted = 0;
    final recurringRuns = <DateTime>[];
    final container = ProviderContainer(
      overrides: [
        auth.authStateProvider.overrideWithValue(const AuthLoggedOut()),
        priceSyncCoordinatorBootstrapProvider.overrideWith((ref) {
          priceSyncStarted++;
        }),
        recurringMaterialiseDueProvider.overrideWith((ref, now) async {
          recurringRuns.add(now);
          return 0;
        }),
      ],
    );
    addTearDown(container.dispose);
    final bootstrapProvider = Provider<void>(financeBackgroundBootstrap);

    container.read(bootstrapProvider);

    expect(priceSyncStarted, 0);
    expect(recurringRuns, hasLength(1));
  });
}
