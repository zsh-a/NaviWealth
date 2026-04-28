import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/providers.dart';
import '../../../data/db/providers.dart';
import '../../../data/domain/amortization_entry.dart';
import '../../../data/domain/liability.dart';
import '../domain/amortization_calculator.dart';
import '../domain/liability_summary.dart';
import 'liability_repository.dart';

/// Current user partition. Auth (FIR-30) will replace this with a real
/// identity from the JWT subject; until then we use a fixed local id so the
/// liability UI can be exercised end-to-end against the encrypted on-device
/// database without an account.
const String kLocalUserId = 'local-user';

final currentUserIdProvider = Provider<String>((ref) => kLocalUserId);

final liabilityRepositoryProvider = FutureProvider<LiabilityRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final deviceId = await ref.watch(deviceIdProviderProvider).getOrCreate();
  final engine = await ref.watch(syncEngineProvider.future);
  return LiabilityRepository(
    db: db,
    ownerUserId: ref.watch(currentUserIdProvider),
    deviceId: deviceId,
    stampHlc: engine.stampHlc,
  );
});

final liabilitiesStreamProvider = StreamProvider<List<Liability>>((ref) async* {
  final repo = await ref.watch(liabilityRepositoryProvider.future);
  yield* repo.watchAll();
});

final liabilityByIdProvider = FutureProvider.family<Liability?, String>((
  ref,
  id,
) async {
  final repo = await ref.watch(liabilityRepositoryProvider.future);
  return repo.getById(id);
});

final amortizationScheduleStreamProvider =
    StreamProvider.family<List<AmortizationEntry>, String>((ref, id) async* {
      final repo = await ref.watch(liabilityRepositoryProvider.future);
      yield* repo.watchSchedule(id);
    });

/// Summary fact pack for one liability — combines the Liability header with
/// its schedule fold. Recomputed whenever either upstream stream emits.
final liabilitySummaryProvider =
    StreamProvider.family<LiabilitySummary?, String>((ref, id) async* {
      final repo = await ref.watch(liabilityRepositoryProvider.future);
      final liability = await repo.getById(id);
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

/// Pure preview of monthly payment for the "add liability" form. Consumers
/// pass principal/rate/term/method as a tuple via [LiabilityPaymentPreview].
final amortizationCalculatorProvider = Provider<AmortizationCalculator>((ref) {
  return AmortizationCalculator();
});
