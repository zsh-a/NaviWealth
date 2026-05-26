import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/finance/data/domain/amortization_entry.dart';
import 'package:naviwealth/features/finance/data/domain/liability.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../core/persistence/providers.dart';
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

final liabilitiesStreamProvider = StreamProvider.autoDispose<List<Liability>>((
  ref,
) async* {
  final repo = await ref.watch(liabilityRepositoryProvider.future);
  yield* repo.watchAll();
});

final liabilityByIdProvider = FutureProvider.autoDispose
    .family<Liability?, String>((ref, id) async {
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

/// All liability summaries in a single provider — avoids per-tile stream
/// subscriptions that are created/destroyed on scroll.
final allLiabilitySummariesProvider =
    StreamProvider.autoDispose<Map<String, LiabilitySummary>>((ref) async* {
      final repo = await ref.watch(liabilityRepositoryProvider.future);
      final liabilities = await ref.watch(liabilitiesStreamProvider.future);
      if (liabilities.isEmpty) {
        yield const {};
        return;
      }
      // Watch all schedules simultaneously by merging their streams.
      // For each liability, compute the summary when its schedule changes.
      final controllers = <String, Stream<List<AmortizationEntry>>>{};
      for (final liab in liabilities) {
        controllers[liab.id] = repo.watchSchedule(liab.id);
      }
      // Merge all schedule streams into a single stream of maps.
      yield* _mergeScheduleStreams(controllers, liabilities).map((schedules) {
        final result = <String, LiabilitySummary>{};
        for (final liab in liabilities) {
          final schedule = schedules[liab.id] ?? const <AmortizationEntry>[];
          result[liab.id] = LiabilitySummary.fromSchedule(
            liability: liab,
            schedule: schedule,
          );
        }
        return result;
      });
    });

Stream<Map<String, List<AmortizationEntry>>> _mergeScheduleStreams(
  Map<String, Stream<List<AmortizationEntry>>> streams,
  List<Liability> liabilities,
) {
  final controller = StreamController<Map<String, List<AmortizationEntry>>>();
  final current = <String, List<AmortizationEntry>>{};
  var completed = 0;
  for (final entry in streams.entries) {
    entry.value.listen(
      (schedule) {
        current[entry.key] = schedule;
        controller.add(Map.of(current));
      },
      onError: controller.addError,
      onDone: () {
        if (++completed == streams.length) controller.close();
      },
    );
  }
  return controller.stream;
}

/// Pure preview of monthly payment for the "add liability" form.
final amortizationCalculatorProvider = Provider<AmortizationCalculator>((ref) {
  return AmortizationCalculator();
});
