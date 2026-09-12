part of 'garmin_sync_controller.dart';

/// Date-only buckets retain the device's local calendar date, not the UTC day
/// of the instant. UTC is used here only for DST-safe date arithmetic.
DateTime garminCalendarDay(DateTime localNow) =>
    DateTime.utc(localNow.year, localNow.month, localNow.day);

class GarminDateRange {
  const GarminDateRange(this.from, this.to);
  final DateTime from;
  final DateTime to;
  int get days => to.difference(from).inDays + 1;
  Iterable<DateTime> get dates sync* {
    for (
      var day = from;
      !day.isAfter(to);
      day = day.add(const Duration(days: 1))
    ) {
      yield day;
    }
  }
}

/// Recent days remain mutable. Historical checks expire after a week, including
/// successful empty responses. Failed ranges are never checkpointed.
List<GarminDateRange> planGarminRefresh({
  required DateTime localNow,
  required Map<String, DateTime> checkedDays,
  Duration window = const Duration(days: 30),
}) {
  final today = garminCalendarDay(localNow);
  final days = window.inDays.clamp(1, 90);
  final recentDays = days.clamp(1, 3);
  final recentFrom = today.subtract(Duration(days: recentDays - 1));
  final ranges = <GarminDateRange>[GarminDateRange(recentFrom, today)];
  final oldest = today.subtract(Duration(days: days - 1));
  var end = recentFrom.subtract(const Duration(days: 1));
  while (!end.isBefore(oldest)) {
    final checked = checkedDays[_garminDayKey(end)];
    if (checked != null &&
        localNow.toUtc().difference(checked) < const Duration(days: 7)) {
      end = end.subtract(const Duration(days: 1));
      continue;
    }
    var start = end;
    while (end.difference(start).inDays < 6) {
      final previous = start.subtract(const Duration(days: 1));
      if (previous.isBefore(oldest)) break;
      final lastChecked = checkedDays[_garminDayKey(previous)];
      if (lastChecked != null &&
          localNow.toUtc().difference(lastChecked) < const Duration(days: 7)) {
        break;
      }
      start = previous;
    }
    ranges.add(GarminDateRange(start, end));
    end = start.subtract(const Duration(days: 1));
  }
  return ranges;
}

String _garminDayKey(DateTime day) => day.toIso8601String().substring(0, 10);
