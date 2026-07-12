import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';

import '../domain/recurrence_engine.dart';
import '../domain/recurring_transaction.dart';
import 'recurring_transaction_repository.dart';

final recurringTransactionRepositoryProvider =
    FutureProvider<RecurringTransactionRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = await ref.watch(outboxStoreProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return RecurringTransactionRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
    });

final recurringMaterialisationServiceProvider =
    FutureProvider<RecurringMaterialisationService>((ref) async {
      final recurringRepo = await ref.watch(
        recurringTransactionRepositoryProvider.future,
      );
      final journalRepo = await ref.watch(
        journalEntryRepositoryProvider.future,
      );
      return RecurringMaterialisationService(
        recurringRepository: recurringRepo,
        journalEntryRepository: journalRepo,
      );
    });

final recurringMaterialiseDueProvider = FutureProvider.family<int, DateTime>((
  ref,
  now,
) async {
  final service = await ref.watch(
    recurringMaterialisationServiceProvider.future,
  );
  return service.materialiseDue(now.toUtc());
});

final recurringTransactionsProvider =
    StreamProvider.autoDispose<List<RecurringTransaction>>((ref) async* {
      final repo = await ref.watch(
        recurringTransactionRepositoryProvider.future,
      );
      yield* repo.watchAll();
    });

final upcomingRecurringEventsProvider = Provider.autoDispose
    .family<List<ForecastedRecurringEvent>, RecurringForecastWindow>((
      ref,
      window,
    ) {
      final rules = (ref.watch(recurringTransactionsProvider).value ?? const [])
          .where((rule) => rule.enabled)
          .toList(growable: false);
      const engine = RecurrenceEngine();
      final events = <ForecastedRecurringEvent>[];
      for (final rule in rules) {
        for (final occurrence in engine.expand(
          rule.rrule,
          rule.nextDueAt,
          window.to,
        )) {
          if (occurrence.isBefore(window.from)) continue;
          events.add(
            ForecastedRecurringEvent(
              recurringTransactionId: rule.id,
              occurrenceDate: occurrence,
              templateJournalBuildJson: rule.templateJournalBuildJson,
            ),
          );
        }
      }
      events.sort((a, b) => a.occurrenceDate.compareTo(b.occurrenceDate));
      return List.unmodifiable(events);
    });

class RecurringForecastWindow {
  const RecurringForecastWindow({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) {
    return other is RecurringForecastWindow &&
        other.from == from &&
        other.to == to;
  }

  @override
  int get hashCode => Object.hash(from, to);
}
