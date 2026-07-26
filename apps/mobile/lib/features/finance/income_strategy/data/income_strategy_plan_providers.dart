import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';

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
