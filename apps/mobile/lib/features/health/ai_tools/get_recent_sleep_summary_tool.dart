/// `get_recent_sleep_summary` — HealthOS device tool
/// (`docs/domains/healthos-domain.md` §4, D-2.4).
///
/// Read-only AI surface over the `sleep_session` rows of
/// `health_metrics`. Returns the last N days of sleep sessions plus a
/// summary (avg hours, total hours, session count). The model uses
/// this when the user asks "how have I been sleeping" / "did I sleep
/// enough last week".
library;

import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/health_metric_source.dart';
import '../data/health_preferences.dart';
import '../data/health_series.dart';
import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class GetRecentSleepSummaryTool implements DeviceTool {
  const GetRecentSleepSummaryTool();

  @override
  String get name => 'get_recent_sleep_summary';

  @override
  String get description =>
      '返回最近 N 天的睡眠会话摘要(每天的入睡时间 + 时长)+ 汇总(按本地醒来日期合计后计算的已记录日平均时长、'
      '总时长、会话数)。数据来自端侧 `health_metrics` 表的 `sleep_session` 类型,'
      '由 HealthKit / Health Connect 适配器同步。'
      '适合场景:"最近一周睡得怎么样" / "周末和工作日睡眠时长对比" / "上次睡过 8 小时是哪天"。'
      '当用户未启用 HealthOS 域或尚未导入睡眠数据时,工具会返回空 `sessions` 列表 + `note`,'
      '此时模型应建议用户在 Settings → Domains 打开 HealthOS 或连接 HealthKit / Health Connect。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'days_back': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 90,
        'default': 7,
        'description': '返回最近多少天的睡眠会话。默认 7,最大 90。',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final daysBack = input['days_back'] is num
        ? (input['days_back'] as num).toInt().clamp(1, 90)
        : 7;
    final repo = await ctx.ref.read(healthMetricRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final now = DateTime.now();
    final preferences = await ctx.ref.read(healthPreferencesProvider.future);
    final window = HealthWindow(now: now, days: daysBack);
    final data = await repo.listInRange(
      ownerUserId: ownerUserId,
      kinds: const {HealthMetricKind.sleepSession},
      from: window.start.subtract(const Duration(days: 2)),
      to: window.end.add(const Duration(days: 1)),
    );
    final rows = buildHealthSeries(
      kind: HealthMetricKind.sleepSession,
      rows: (data[HealthMetricKind.sleepSession] ?? const [])
          .where((row) => _completed(row, now))
          .toList(),
      window: window,
      preferredSource: preferences.sources[HealthMetricKind.sleepSession],
    ).samples.reversed.expand((day) => day.records).toList();
    final result = shape(rows, daysBack: daysBack, now: now);
    return withEvidence(
      result: result,
      anchors: rows
          .take(8)
          .map(
            (metric) => EvidenceAnchor(
              entityTable: 'health_metrics',
              entityId: metric.id,
              label:
                  'Sleep · ${metric.capturedAt.toLocal().toIso8601String().substring(0, 10)}',
            ),
          ),
    );
  }

  /// Pure shaper — exposed for unit tests so the round-trip from raw
  /// [HealthMetric] rows to the JSON wire payload can be exercised
  /// without a Drift database.
  static Map<String, Object?> shape(
    List<HealthMetric> rows, {
    required int daysBack,
    required DateTime now,
    HealthMetricSource? preferredSource,
  }) {
    final window = HealthWindow(now: now, days: daysBack);
    final series = buildHealthSeries(
      kind: HealthMetricKind.sleepSession,
      rows: rows.where((row) => _completed(row, now)).toList(),
      window: window,
      preferredSource: preferredSource,
    );
    final inWindow = series.samples.reversed.expand((day) => day.records);

    final sessions = <Map<String, Object?>>[];
    double totalHours = 0;
    for (final m in inWindow) {
      final hours = _secondsToHours(m.value, m.unit);
      totalHours += hours;
      sessions.add(<String, Object?>{
        'started_at': _toIso(m.capturedAt),
        'duration_hours': _round(hours),
        if (m.sourceDevice != null) 'source_device': m.sourceDevice,
      });
    }
    final count = sessions.length;
    final avgHours = series.average ?? 0;

    return <String, Object?>{
      'from': _toIso(window.start),
      'to': _toIso(now),
      'sessions': sessions,
      'summary': <String, Object?>{
        'session_count': count,
        'total_hours': _round(totalHours),
        'average_hours': _round(avgHours),
        'observed_days': series.recordedDays,
      },
      if (count == 0)
        'note':
            'HealthOS 域尚无睡眠记录。建议用户在 Settings → Domains 启用 Health,然后从 '
            'HealthKit / Health Connect 导入睡眠数据。',
    };
  }

  static String _toIso(DateTime d) => d.toUtc().toIso8601String();

  static bool _completed(HealthMetric row, DateTime now) =>
      row.kind == HealthMetricKind.sleepSession &&
      row.value.isFinite &&
      row.value >= 0 &&
      const ['s', 'min', 'h'].contains(row.unit) &&
      row.sync.deletedAt == null &&
      !row.capturedAt
          .add(Duration(seconds: healthDurationSeconds(row).round()))
          .isAfter(now);

  static double _secondsToHours(double value, String unit) {
    return switch (unit) {
      's' => value / 3600.0,
      'min' => value / 60.0,
      'h' => value,
      _ => value / 3600.0, // assume seconds when unit is unfamiliar
    };
  }

  static double _round(double v) => (v * 100).round() / 100.0;
}
