enum RecurrenceFrequency { daily, weekly, monthly, yearly }

class RecurrenceRule {
  const RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    this.byMonthDay,
    this.until,
  }) : assert(interval > 0);

  final RecurrenceFrequency frequency;
  final int interval;
  final int? byMonthDay;
  final DateTime? until;
}

class RecurrenceParseException implements Exception {
  const RecurrenceParseException(this.message);

  final String message;

  @override
  String toString() => 'RecurrenceParseException: $message';
}

class RecurrenceEngine {
  const RecurrenceEngine();

  List<DateTime> expand(String rrule, DateTime from, DateTime to) {
    if (to.isBefore(from)) return const <DateTime>[];
    final rule = parse(rrule);
    final start = _dateOnlyUtc(from);
    final end = _dateOnlyUtc(to);
    final until = rule.until == null ? null : _dateOnlyUtc(rule.until!);
    final out = <DateTime>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      if (until != null && cursor.isAfter(until)) break;
      out.add(cursor);
      cursor = nextAfter(rule, cursor);
    }
    return List.unmodifiable(out);
  }

  DateTime nextAfterRule(String rrule, DateTime after) =>
      nextAfter(parse(rrule), after);

  DateTime firstOnOrAfterRule(String rrule, DateTime start) =>
      firstOnOrAfter(parse(rrule), start);

  /// Returns the first occurrence on or after [start].
  DateTime firstOnOrAfter(RecurrenceRule rule, DateTime start) {
    final cursor = _dateOnlyUtc(start);
    final targetDay = rule.byMonthDay;
    if (targetDay == null ||
        rule.frequency == RecurrenceFrequency.daily ||
        rule.frequency == RecurrenceFrequency.weekly) {
      return cursor;
    }
    if (rule.frequency == RecurrenceFrequency.monthly) {
      var year = cursor.year;
      var month = cursor.month;
      while (true) {
        if (_isValidDay(year, month, targetDay)) {
          final candidate = DateTime.utc(year, month, targetDay);
          if (!candidate.isBefore(cursor)) return candidate;
        }
        final next = DateTime.utc(year, month + rule.interval);
        year = next.year;
        month = next.month;
      }
    }
    var year = cursor.year;
    while (true) {
      if (_isValidDay(year, cursor.month, targetDay)) {
        final candidate = DateTime.utc(year, cursor.month, targetDay);
        if (!candidate.isBefore(cursor)) return candidate;
      }
      year += rule.interval;
    }
  }

  /// Advances [nextDueAt] to the first occurrence on or after [date].
  DateTime advanceToOnOrAfter(
    RecurrenceRule rule,
    DateTime nextDueAt,
    DateTime date,
  ) {
    final target = _dateOnlyUtc(date);
    var due = _dateOnlyUtc(nextDueAt);
    while (due.isBefore(target)) {
      due = nextAfter(rule, due);
    }
    return due;
  }

  DateTime nextAfter(RecurrenceRule rule, DateTime after) {
    final cursor = _dateOnlyUtc(after);
    return switch (rule.frequency) {
      RecurrenceFrequency.daily => cursor.add(Duration(days: rule.interval)),
      RecurrenceFrequency.weekly => cursor.add(
        Duration(days: 7 * rule.interval),
      ),
      RecurrenceFrequency.monthly => _addMonths(cursor, rule.interval, rule),
      RecurrenceFrequency.yearly => _addYears(cursor, rule.interval, rule),
    };
  }

  RecurrenceRule parse(String rrule) {
    final parts = <String, String>{};
    for (final raw in rrule.split(';')) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      final idx = part.indexOf('=');
      if (idx <= 0 || idx == part.length - 1) {
        throw const RecurrenceParseException('Invalid RRULE part.');
      }
      parts[part.substring(0, idx).toUpperCase()] = part
          .substring(idx + 1)
          .toUpperCase();
    }
    final freqRaw = parts['FREQ'];
    if (freqRaw == null) {
      throw const RecurrenceParseException('RRULE must include FREQ.');
    }
    final frequency = switch (freqRaw) {
      'DAILY' => RecurrenceFrequency.daily,
      'WEEKLY' => RecurrenceFrequency.weekly,
      'MONTHLY' => RecurrenceFrequency.monthly,
      'YEARLY' => RecurrenceFrequency.yearly,
      _ => throw RecurrenceParseException('Unsupported FREQ: $freqRaw.'),
    };
    final interval = int.tryParse(parts['INTERVAL'] ?? '1');
    if (interval == null || interval <= 0) {
      throw const RecurrenceParseException('INTERVAL must be a positive int.');
    }
    final byMonthDay = parts.containsKey('BYMONTHDAY')
        ? int.tryParse(parts['BYMONTHDAY']!)
        : null;
    if (parts.containsKey('BYMONTHDAY') &&
        (byMonthDay == null || byMonthDay < 1 || byMonthDay > 31)) {
      throw const RecurrenceParseException('BYMONTHDAY must be 1..31.');
    }
    return RecurrenceRule(
      frequency: frequency,
      interval: interval,
      byMonthDay: byMonthDay,
      until: parts.containsKey('UNTIL') ? _parseUntil(parts['UNTIL']!) : null,
    );
  }

  DateTime _addMonths(DateTime cursor, int interval, RecurrenceRule rule) {
    final targetDay = rule.byMonthDay ?? cursor.day;
    var monthIndex = cursor.month - 1 + interval;
    while (true) {
      final year = cursor.year + monthIndex ~/ 12;
      final month = monthIndex % 12 + 1;
      if (_isValidDay(year, month, targetDay)) {
        return DateTime.utc(year, month, targetDay);
      }
      monthIndex += interval;
    }
  }

  DateTime _addYears(DateTime cursor, int interval, RecurrenceRule rule) {
    final targetDay = rule.byMonthDay ?? cursor.day;
    var year = cursor.year + interval;
    while (true) {
      if (_isValidDay(year, cursor.month, targetDay)) {
        return DateTime.utc(year, cursor.month, targetDay);
      }
      year += interval;
    }
  }

  static DateTime _dateOnlyUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static DateTime _parseUntil(String raw) {
    if (RegExp(r'^\d{8}$').hasMatch(raw)) {
      return DateTime.utc(
        int.parse(raw.substring(0, 4)),
        int.parse(raw.substring(4, 6)),
        int.parse(raw.substring(6, 8)),
      );
    }
    if (RegExp(r'^\d{8}T\d{6}Z$').hasMatch(raw)) {
      return DateTime.utc(
        int.parse(raw.substring(0, 4)),
        int.parse(raw.substring(4, 6)),
        int.parse(raw.substring(6, 8)),
        int.parse(raw.substring(9, 11)),
        int.parse(raw.substring(11, 13)),
        int.parse(raw.substring(13, 15)),
      );
    }
    return DateTime.parse(raw).toUtc();
  }

  static bool _isValidDay(int year, int month, int day) {
    final candidate = DateTime.utc(year, month, day);
    return candidate.year == year &&
        candidate.month == month &&
        candidate.day == day;
  }
}
