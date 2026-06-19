import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/drift_query_plan_executor.dart';
import 'package:naviwealth/features/finance/command_palette/finance_query_plan_executor_provider.dart';
import 'package:naviwealth/features/finance/composition/finance_bootstrap.dart';

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
}
