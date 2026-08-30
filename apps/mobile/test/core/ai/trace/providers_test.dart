import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/trace/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';

import '../../persistence/test_database.dart';

void main() {
  test('trace writes refresh recent and detail providers', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((_) async => db)],
    );
    addTearDown(container.dispose);
    await container.read(appDatabaseProvider.future);

    final recentSubscription = container.listen(
      recentAiTracesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final detailSubscription = container.listen(
      aiTraceByIdProvider('rewrite-1'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(recentSubscription.close);
    addTearDown(detailSubscription.close);

    expect(await container.read(recentAiTracesProvider.future), isEmpty);
    expect(
      await container.read(aiTraceByIdProvider('rewrite-1').future),
      isNull,
    );

    const trace = AiTrace(
      requestId: 'rewrite-1',
      startedAtIso: '2026-08-30T00:00:00.000Z',
      intent: IntentHint(
        capability: Capability.analyze,
        risk: RiskLevel.info,
        label: 'knowledge_rewrite',
        domain: 'knowledge',
      ),
      backend: Backend.device,
      budgetTier: BudgetTier.standard,
      routingReason: 'frb_agent_runtime_profile',
      totalDurationMs: 10,
    );
    await container.read(aiTraceStoreProvider).append(trace);

    expect(
      (await container.read(recentAiTracesProvider.future)).single.requestId,
      'rewrite-1',
    );
    expect(
      (await container.read(aiTraceByIdProvider('rewrite-1').future))
          ?.requestId,
      'rewrite-1',
    );
  });
}
