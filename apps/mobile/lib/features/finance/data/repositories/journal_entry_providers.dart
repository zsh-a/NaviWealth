import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';

import 'journal_entry_repository.dart';
import 'providers.dart';

/// Provider tree for the ledger write and read paths. Lives in its own
/// file so `providers.dart` stays focused on shared repository wiring.
///
/// Composition:
///   * [_FxRateLookupAdapter] satisfies the `FxRateSource` contract
///     [JournalEntryRepository] needs by delegating to the existing
///     [FxRateLookup] read model. Multiple-currency journal entries
///     consult it during the Σ(weight) = 0 invariant check; same-
///     currency entries take a fast path back from
///     `IdentityFxRateSource.rate(from == to)`.
///   * [currentFxLookupProvider] holds an in-memory [FxRateLookup]
///     built off the live `fx_rates` stream. Rebuilds whenever a new
///     rate lands so journal-entry writes always see fresh FX data
///     without the repo having to re-query SQLite per leg.
///   * [journalEntryRepositoryProvider] composes everything into a
///     single [JournalEntryRepository] keyed off the user's current
///     base currency.

class _FxRateLookupAdapter implements FxRateSource {
  const _FxRateLookupAdapter(this._lookup);

  final FxRateLookup _lookup;

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) {
    if (from == to) return Decimal.one;
    final fxRate = _lookup.rateFor(from, to, on: asOf);
    return fxRate?.rate;
  }
}

final currentFxLookupProvider = Provider<FxRateLookup>((ref) {
  // The stream provider hydrates from Drift; while the first frame is
  // resolving we serve an empty lookup, which the
  // [_FxRateLookupAdapter] turns into `null` for any non-identity
  // pair. Single-currency transfers never touch this branch, so
  // they keep working through the cold start.
  final rates = ref.watch(fxRatesStreamProvider).asData?.value ?? const [];
  return InMemoryFxRateLookup(rates);
});

final journalEntryRepositoryProvider = FutureProvider<JournalEntryRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  final lookup = ref.watch(currentFxLookupProvider);
  final base = ref.watch(baseCurrencyProvider);
  return JournalEntryRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
    fxRateSource: _FxRateLookupAdapter(lookup),
    baseCurrency: base,
  );
});

/// Live stream of every non-deleted journal entry with its postings,
/// ordered by `(date DESC, id ASC)`. Subscribers (journal list page,
/// net-worth derivations) get a fresh snapshot whenever a JE write
/// lands.
final journalEntriesWithPostingsStreamProvider =
    StreamProvider.autoDispose<List<JournalEntryWithPostings>>((ref) async* {
      final repo = await ref.watch(journalEntryRepositoryProvider.future);
      yield* repo.watchAllWithPostings();
    });

/// Live stream of expense entries materialised from the journal.
final journalExpensesStreamProvider = StreamProvider.autoDispose<List<Expense>>(
  (ref) async* {
    final repo = await ref.watch(journalEntryRepositoryProvider.future);
    yield* repo.watchExpenses();
  },
);
