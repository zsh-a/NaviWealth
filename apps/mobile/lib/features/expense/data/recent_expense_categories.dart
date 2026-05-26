import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';

/// Window used to compute the "most-used recently" expense account that
/// the form pre-selects on first open. A short window keeps the default
/// responsive to changing habits.
const Duration kRecentExpenseCategoryWindow = Duration(days: 30);

/// The expense account id the user picked most often inside
/// [kRecentExpenseCategoryWindow]. Returns `null` while the underlying
/// stream is still loading or when the user has no recent spends.
final mostUsedExpenseCategoryProvider = Provider<String?>((ref) {
  final expensesAsync = ref.watch(journalExpensesStreamProvider);
  return expensesAsync.maybeWhen(
    data: (expenses) {
      if (expenses.isEmpty) return null;
      final cutoff = DateTime.now().subtract(kRecentExpenseCategoryWindow);
      final freq = <String, int>{};
      for (final e in expenses) {
        if (e.tradeDate.isBefore(cutoff)) continue;
        freq.update(e.expenseAccountId, (v) => v + 1, ifAbsent: () => 1);
      }
      if (freq.isEmpty) return null;
      String? topId;
      var topCount = -1;
      for (final entry in freq.entries) {
        if (entry.value > topCount) {
          topCount = entry.value;
          topId = entry.key;
        }
      }
      return topId;
    },
    orElse: () => null,
  );
});
