import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';

/// One calendar-day bucket on the activity timeline.
class ActivityDaySection {
  const ActivityDaySection({
    required this.day,
    required this.entries,
    required this.expenseTotal,
    required this.incomeTotal,
    required this.unit,
  });

  /// Local calendar day (time truncated to midnight).
  final DateTime day;

  final List<JournalEntryWithPostings> entries;

  /// Sum of absolute expense/payment headline amounts for [unit].
  final Decimal expenseTotal;

  /// Sum of absolute income headline amounts for [unit].
  final Decimal incomeTotal;

  /// Display unit for day totals (first dominant headline unit).
  final String unit;

  bool get hasExpense => expenseTotal > Decimal.zero;
  bool get hasIncome => incomeTotal > Decimal.zero;
}

/// Groups entries by local calendar day, newest day first.
///
/// Within each day, preserves the input order (repo already sorts desc).
List<ActivityDaySection> groupActivityEntriesByDay(
  List<JournalEntryWithPostings> entries, {
  required Map<String, Account> accountsById,
  DateTime? now,
}) {
  if (entries.isEmpty) return const [];

  final buckets = <DateTime, List<JournalEntryWithPostings>>{};
  for (final entry in entries) {
    final d = entry.entry.date;
    final day = DateTime(d.year, d.month, d.day);
    buckets.putIfAbsent(day, () => <JournalEntryWithPostings>[]).add(entry);
  }

  final days = buckets.keys.toList(growable: false)
    ..sort((a, b) => b.compareTo(a));

  return [
    for (final day in days)
      _buildDaySection(
        day: day,
        entries: buckets[day]!,
        accountsById: accountsById,
      ),
  ];
}

ActivityDaySection _buildDaySection({
  required DateTime day,
  required List<JournalEntryWithPostings> entries,
  required Map<String, Account> accountsById,
}) {
  var expense = Decimal.zero;
  var income = Decimal.zero;
  var unit = 'CNY';
  final unitCounts = <String, int>{};

  for (final entry in entries) {
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final headline = activityHeadlinePosting(entry.postings, accountsById);
    if (headline == null) continue;
    unitCounts[headline.unit] = (unitCounts[headline.unit] ?? 0) + 1;
    final mag = headline.units.abs();
    switch (classification.kind) {
      case EntryKind.expense:
      case EntryKind.payment:
        expense += mag;
      case EntryKind.income:
        income += mag;
      case EntryKind.trade:
      case EntryKind.transfer:
      case EntryKind.adjustment:
      case EntryKind.opening:
      case EntryKind.other:
        break;
    }
  }

  if (unitCounts.isNotEmpty) {
    unit = unitCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  return ActivityDaySection(
    day: day,
    entries: entries,
    expenseTotal: expense,
    incomeTotal: income,
    unit: unit,
  );
}

/// Shared headline posting picker for feed rows, day totals, and previews.
Posting? activityHeadlinePosting(
  List<Posting> postings,
  Map<String, Account> accounts,
) {
  Posting? headline;
  Decimal? best;
  Posting? fallback;
  Decimal? fallbackBest;
  for (final p in postings) {
    final magnitude = p.units.abs();
    if (fallbackBest == null || magnitude > fallbackBest) {
      fallbackBest = magnitude;
      fallback = p;
    }
    final account = accounts[p.accountId];
    if (account == null) continue;
    if (account.category != AccountSide.asset &&
        account.category != AccountSide.liability) {
      continue;
    }
    if (best == null || magnitude > best) {
      best = magnitude;
      headline = p;
    }
  }
  return headline ?? fallback;
}

/// Lightweight in/out totals across a loaded page (for the summary strip).
class ActivityPageTotals {
  const ActivityPageTotals({
    required this.expenseTotal,
    required this.incomeTotal,
    required this.unit,
    required this.count,
  });

  final Decimal expenseTotal;
  final Decimal incomeTotal;
  final String unit;
  final int count;

  static ActivityPageTotals fromEntries(
    List<JournalEntryWithPostings> entries, {
    required Map<String, Account> accountsById,
  }) {
    var expense = Decimal.zero;
    var income = Decimal.zero;
    var unit = 'CNY';
    final unitCounts = <String, int>{};
    for (final entry in entries) {
      final classification = classifyEntryKind(
        postings: entry.postings,
        resolveCategory: (id) => accountsById[id]?.category,
      );
      final headline = activityHeadlinePosting(entry.postings, accountsById);
      if (headline == null) continue;
      unitCounts[headline.unit] = (unitCounts[headline.unit] ?? 0) + 1;
      final mag = headline.units.abs();
      switch (classification.kind) {
        case EntryKind.expense:
        case EntryKind.payment:
          expense += mag;
        case EntryKind.income:
          income += mag;
        default:
          break;
      }
    }
    if (unitCounts.isNotEmpty) {
      unit = unitCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }
    return ActivityPageTotals(
      expenseTotal: expense,
      incomeTotal: income,
      unit: unit,
      count: entries.length,
    );
  }
}
