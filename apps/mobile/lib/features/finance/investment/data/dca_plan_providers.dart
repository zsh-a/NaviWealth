import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';

import '../domain/dca/dca_plan.dart';
import 'dca_plan_repository.dart';

final dcaPlanRepositoryProvider = FutureProvider<DcaPlanRepository>((
  ref,
) async {
  return DcaPlanRepository(
    db: await ref.watch(appDatabaseProvider.future),
    outbox: await ref.watch(outboxStoreProvider.future),
    stamper: await ref.watch(mutationStamperProvider.future),
  );
});

final dcaPlansProvider = StreamProvider.autoDispose<List<DcaPlan>>((
  ref,
) async* {
  final repository = await ref.watch(dcaPlanRepositoryProvider.future);
  yield* repository.watchAll();
});
