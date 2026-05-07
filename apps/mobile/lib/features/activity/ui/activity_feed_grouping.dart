import '../../../data/repositories/journal_entry_repository.dart';

enum ActivityDateGroup { today, yesterday, thisWeek, earlier }

class ActivityDateSection {
  const ActivityDateSection({required this.group, required this.entries});

  final ActivityDateGroup group;
  final List<JournalEntryWithPostings> entries;
}

List<ActivityDateSection> groupActivityEntriesByDate(
  List<JournalEntryWithPostings> entries,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(Duration(days: today.weekday - 1));

  final map = <ActivityDateGroup, List<JournalEntryWithPostings>>{};
  for (final e in entries) {
    final d = DateTime(e.entry.date.year, e.entry.date.month, e.entry.date.day);
    final group = d.isAtSameMomentAs(today)
        ? ActivityDateGroup.today
        : d.isAtSameMomentAs(yesterday)
        ? ActivityDateGroup.yesterday
        : !d.isBefore(weekStart)
        ? ActivityDateGroup.thisWeek
        : ActivityDateGroup.earlier;
    map.putIfAbsent(group, () => []).add(e);
  }

  return [
    for (final g in ActivityDateGroup.values)
      if (map[g]?.isNotEmpty ?? false)
        ActivityDateSection(group: g, entries: map[g]!),
  ];
}
