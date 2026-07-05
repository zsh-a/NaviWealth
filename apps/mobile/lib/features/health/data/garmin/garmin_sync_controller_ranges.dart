part of 'garmin_sync_controller.dart';

mixin GarminSyncControllerRangeMixin on Notifier<GarminSyncState> {
  Future<List<_GarminDateRange>> _missingGarminRanges({
    required DateTime now,
    required Duration window,
  }) async {
    final to = _dayStartUtc(now);
    final from = to.subtract(Duration(days: window.inDays));
    final expected = <DateTime>[
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) d,
    ];
    final covered = await _garminCoveredDays(limit: expected.length + 10);
    final missing = expected
        .where((day) => !covered.contains(day))
        .toList(growable: false);
    return _compressDays(missing);
  }

  Future<Set<DateTime>> _garminCoveredDays({required int limit}) async {
    final repo = await ref.read(healthMetricRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final rows = await repo.listByKinds(
      ownerUserId: userId,
      kinds: _kGarminCoverageKinds,
      limit: limit,
    );
    final covered = <DateTime>{};
    for (final metrics in rows.values) {
      for (final metric in metrics) {
        if (!_isGarminMetric(metric)) continue;
        covered.add(_dayStartUtc(metric.capturedAt));
      }
    }
    return covered;
  }

  List<_GarminDateRange> _compressDays(List<DateTime> days) {
    if (days.isEmpty) return const <_GarminDateRange>[];
    final sorted = List<DateTime>.of(days)..sort();
    final ranges = <_GarminDateRange>[];
    var start = sorted.first;
    var end = sorted.first;
    for (final day in sorted.skip(1)) {
      if (day.difference(end).inDays == 1) {
        end = day;
        continue;
      }
      ranges.add(_GarminDateRange(start, end));
      start = day;
      end = day;
    }
    ranges.add(_GarminDateRange(start, end));
    return ranges;
  }

  bool _isGarminMetric(HealthMetric metric) {
    return metric.id.startsWith('garmin:') ||
        (metric.sourceDevice?.toLowerCase() == 'garmin');
  }

  DateTime _dayStartUtc(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}

class _GarminDateRange {
  const _GarminDateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  int get days => to.difference(from).inDays + 1;

  String get label =>
      days == 1 ? _formatDay(from) : '${_formatDay(from)}..${_formatDay(to)}';

  static String _formatDay(DateTime value) {
    final utc = value.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }
}
