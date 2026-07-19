import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/persistence/providers.dart';
import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/outbox_provider.dart';
import '../domain/monthly_close.dart';
import 'monthly_close_repository.dart';

final monthlyCloseNowProvider = Provider<DateTime>((ref) => DateTime.now());

final currentClosePeriodProvider = Provider<String>((ref) {
  final now = ref.watch(monthlyCloseNowProvider);
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}';
});

final monthlyCloseRepositoryProvider = FutureProvider<MonthlyCloseRepository>((
  ref,
) async {
  return MonthlyCloseRepository(
    db: await ref.watch(appDatabaseProvider.future),
    outbox: await ref.watch(outboxStoreProvider.future),
    stamper: await ref.watch(mutationStamperProvider.future),
  );
});

final currentMonthlyCloseProvider = StreamProvider.autoDispose<MonthlyClose?>((
  ref,
) async* {
  final repository = await ref.watch(monthlyCloseRepositoryProvider.future);
  yield* repository.watch(ref.watch(currentClosePeriodProvider));
});
