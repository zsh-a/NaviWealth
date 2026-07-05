import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import '../domain/account_balances.dart';

/// All non-zero per-unit balances, keyed by accountId. Drives the
/// Accounts Hub multi-currency rows: each entry expands into one
/// [AccountBalanceLeg] per currency / asset symbol the account holds.
///
/// Single bulk subscription against [JournalEntryRepository] —
/// rebuilds only when posting deltas land. Sorted with fiat-like legs
/// (no `:`) before asset legs so the list order is stable.
final accountBalancesByIdProvider =
    StreamProvider<Map<String, AccountBalances>>((ref) async* {
      final manualRepo = await ref.watch(manualAssetRepositoryProvider.future);
      await manualRepo.repairCashBalancePostings();
      final repo = await ref.watch(journalEntryRepositoryProvider.future);
      yield* repo.watchBalancesByUnit().map((byAccount) {
        return {
          for (final entry in byAccount.entries)
            entry.key: _build(entry.key, entry.value),
        };
      });
    });

AccountBalances _build(String accountId, Map<String, Decimal> raw) {
  final legs = <AccountBalanceLeg>[
    for (final e in raw.entries) AccountBalanceLeg(unit: e.key, units: e.value),
  ];
  // Fiat / cash legs first (alphabetical), asset legs after (also
  // alphabetical) so the user sees "USD · HKD · CNY" before "AAPL · ETH".
  legs.sort((a, b) {
    if (a.isFiatLike != b.isFiatLike) {
      return a.isFiatLike ? -1 : 1;
    }
    return a.unit.compareTo(b.unit);
  });
  return AccountBalances(accountId: accountId, legs: legs);
}
