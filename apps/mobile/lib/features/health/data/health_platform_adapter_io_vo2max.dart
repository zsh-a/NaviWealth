part of 'health_platform_adapter_io.dart';

Future<bool> _requestIosVo2MaxAuthorization() async {
  try {
    return await _healthKitChannel.invokeMethod<bool>(
          'requestVo2MaxAuthorization',
        ) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

Future<List<RawDailyValue>> _fetchIosVo2Max({
  required DateTime from,
  required DateTime to,
}) async {
  if (!Platform.isIOS) return const <RawDailyValue>[];
  try {
    final rows = await _healthKitChannel.invokeListMethod<Object?>(
      'readVo2Max',
      <String, Object?>{
        'from': from.toUtc().millisecondsSinceEpoch,
        'to': to.toUtc().millisecondsSinceEpoch,
      },
    );
    if (rows == null || rows.isEmpty) return const <RawDailyValue>[];
    return _dailyAverageVo2Max(rows);
  } on MissingPluginException {
    return const <RawDailyValue>[];
  } on PlatformException {
    return const <RawDailyValue>[];
  }
}

List<RawDailyValue> _dailyAverageVo2Max(List<Object?> rows) {
  final buckets = <String, _DailyBucket>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final value = (row['value'] as num?)?.toDouble();
    final measuredAtMs = (row['measured_at_ms'] as num?)?.toInt();
    if (value == null || measuredAtMs == null) continue;
    final measuredAt = DateTime.fromMillisecondsSinceEpoch(
      measuredAtMs,
      isUtc: true,
    );
    final dayKey = _dayKeyUtc(measuredAt);
    final bucket = buckets.putIfAbsent(
      dayKey,
      () =>
          _DailyBucket(dayKey: dayKey, source: row['source_device'] as String?),
    );
    bucket.add(value);
  }
  return buckets.values
      .map(
        (b) => b.toDaily(
          externalId: 'hk:vo2_max:${b.dayKey}',
          reduce: _Reduce.average,
        ),
      )
      .toList(growable: false);
}
