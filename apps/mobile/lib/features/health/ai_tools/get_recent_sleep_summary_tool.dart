/// `get_recent_sleep_summary` — HealthOS device tool
/// (`docs/domains/healthos-domain.md` §4, D-2.4).
///
/// Read-only AI surface over the `sleep_session` rows of
/// `health_metrics`. Returns the last N days of sleep sessions plus a
/// summary (avg hours, total hours, session count). The model uses
/// this when the user asks "how have I been sleeping" / "did I sleep
/// enough last week".
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class GetRecentSleepSummaryTool implements DeviceTool {
  const GetRecentSleepSummaryTool();

  @override
  String get name => 'get_recent_sleep_summary';

  @override
  String get description =>
      '返回最近 N 天的睡眠会话摘要(每天的入睡时间 + 时长)+ 汇总(平均时长、'
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

    // We pull a generous limit; the repo orders by capturedAt desc, so
    // taking the first ~daysBack*1.5 rows covers most patterns (multiple
    // naps in a day, daytime sessions). Then we filter to the window in
    // [shape] for the final output.
    final rows = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.sleepSession,
      limit: (daysBack * 1.5).ceil().clamp(10, 200),
    );
    final now = DateTime.now().toUtc();
    return shape(rows, daysBack: daysBack, now: now);
  }

  /// Pure shaper — exposed for unit tests so the round-trip from raw
  /// [HealthMetric] rows to the JSON wire payload can be exercised
  /// without a Drift database.
  static Map<String, Object?> shape(
    List<HealthMetric> rows, {
    required int daysBack,
    required DateTime now,
  }) {
    final fromInstant = now.subtract(Duration(days: daysBack));
    final inWindow = rows.where(
      (m) => !m.capturedAt.isBefore(fromInstant) && !m.capturedAt.isAfter(now),
    );

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
    final avgHours = count == 0 ? 0.0 : totalHours / count;

    return <String, Object?>{
      'from': _toIso(fromInstant),
      'to': _toIso(now),
      'sessions': sessions,
      'summary': <String, Object?>{
        'session_count': count,
        'total_hours': _round(totalHours),
        'average_hours': _round(avgHours),
      },
      if (count == 0)
        'note':
            'HealthOS 域尚无睡眠记录。建议用户在 Settings → Domains 启用 Health,然后从 '
            'HealthKit / Health Connect 导入睡眠数据。',
    };
  }

  static String _toIso(DateTime d) => d.toUtc().toIso8601String();

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
