import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/providers.dart';
import '../../../data/domain/amortization_entry.dart';
import '../../../data/domain/liability.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../data/repositories/providers.dart';
import '../domain/amortization_calculator.dart';
import '../domain/liability_summary.dart';
import 'liability_repository.dart';

final liabilityRepositoryProvider = FutureProvider<LiabilityRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  final jeRepo = await ref.watch(journalEntryRepositoryProvider.future);
  return LiabilityRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
    journalEntryRepo: jeRepo,
  );
});

final liabilitiesStreamProvider =
    StreamProvider.autoDispose<List<Liability>>((ref) async* {
  final repo = await ref.watch(liabilityRepositoryProvider.future);
  yield* repo.watchAll();
});

final liabilityByIdProvider =
    FutureProvider.autoDispose.family<Liability?, String>((ref, id) async {
  final repo = await ref.watch(liabilityRepositoryProvider.future);
  return repo.findById(id);
});

final amortizationScheduleStreamProvider = StreamProvider.autoDispose
    .family<List<AmortizationEntry>, String>((ref, id) async* {
  final repo = await ref.watch(liabilityRepositoryProvider.future);
  yield* repo.watchSchedule(id);
});

/// Summary fact pack for one liability — combines the Liability header with
/// its schedule fold. Recomputed whenever either upstream stream emits.
final liabilitySummaryProvider = StreamProvider.autoDispose
    .family<LiabilitySummary?, String>((ref, id) async* {
  final repo = await ref.watch(liabilityRepositoryProvider.future);
  final liability = await repo.findById(id);
  if (liability == null) {
    yield null;
    return;
  }
  await for (final schedule in repo.watchSchedule(id)) {
    yield LiabilitySummary.fromSchedule(
      liability: liability,
      schedule: schedule,
    );
  }
});

/// Pure preview of monthly payment for the "add liability" form.
final amortizationCalculatorProvider = Provider<AmortizationCalculator>((ref) {
  return AmortizationCalculator();
});
