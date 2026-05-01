import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/providers.dart';

/// Window used to compute the "most-used recently" expense category that
/// the form pre-selects on first open. Matches the FIR-95 spec ("近 30 天
/// 频次"). A short window keeps the default responsive to changing habits
/// (e.g. travel weeks) instead of being dominated by all-time baseline.
const Duration kRecentExpenseCategoryWindow = Duration(days: 30);

/// The category id the user picked most often inside
/// [kRecentExpenseCategoryWindow]. Returns `null` while the underlying
/// stream is still loading or when the user has no recent spends, so
/// callers fall back to the seeded "其它" bucket the form already uses.
final mostUsedExpenseCategoryProvider = Provider<String?>((ref) {
  final expensesAsync = ref.watch(expensesStreamProvider);
  return expensesAsync.maybeWhen(
    data: (expenses) {
      if (expenses.isEmpty) return null;
      final cutoff = DateTime.now().subtract(kRecentExpenseCategoryWindow);
      final freq = <String, int>{};
      for (final e in expenses) {
        if (e.tradeDate.isBefore(cutoff)) continue;
        freq.update(e.categoryId, (v) => v + 1, ifAbsent: () => 1);
      }
      if (freq.isEmpty) return null;
      String? topId;
      var topCount = -1;
      // `MapEntry` iteration order is insertion order on Dart maps; ties
      // therefore pick the first-seen category, which keeps the choice
      // stable across rebuilds for the same input list.
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
