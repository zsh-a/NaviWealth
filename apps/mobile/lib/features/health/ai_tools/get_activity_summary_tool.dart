/// `get_activity_summary` — HealthOS device tool
/// (`docs/healthos-domain.md` §4, D-2.4).
///
/// Read-only AI surface that joins `steps_daily` + `active_energy_daily`
/// per calendar day. Returns per-day records plus totals / averages
/// over the requested window.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class GetActivitySummaryTool implements DeviceTool {
  const GetActivitySummaryTool();

  @override
  String get name => 'get_activity_summary';

  @override
  String get description =>
      '返回最近 N 天的每日活动汇总:步数 + 主动消耗卡路里 (active energy)。'
      '数据来自端侧 `health_metrics` 表的 `steps_daily` 和 `active_energy_daily` 类型,'
      '按日期 join。'
      '适合场景:"最近一周走了多少步" / "周末和工作日的活动差异" / "今天步数够不够"。'
      '当 HealthOS 未启用或缺少其中一类数据时,对应字段会留为 null;'
      '完全空 (两类都空) 时返回空 `days` + `note`,建议用户启用 Health。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'days_back': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 90,
        'default': 7,
        'description': '返回最近多少天。默认 7,最大 90。',
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

    final stepRows = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.stepsDaily,
      limit: daysBack + 5,
    );
    final energyRows = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.activeEnergyDaily,
      limit: daysBack + 5,
    );
    final now = DateTime.now().toUtc();
    return shape(
      steps: stepRows,
      energy: energyRows,
      daysBack: daysBack,
      now: now,
    );
  }

  /// Pure shaper — exposed for unit tests.
  static Map<String, Object?> shape({
    required List<HealthMetric> steps,
    required List<HealthMetric> energy,
    required int daysBack,
    required DateTime now,
  }) {
    final fromInstant = now.subtract(Duration(days: daysBack));

    // Bucket by ISO date (YYYY-MM-DD). Within a day, latest reading wins
    // (later sync overrides an earlier partial number).
    String dayKey(DateTime d) => d.toUtc().toIso8601String().substring(0, 10);
    bool inWindow(DateTime d) =>
        !d.isBefore(fromInstant) && !d.isAfter(now);

    final stepsByDay = <String, double>{};
    final stepsCapturedAt = <String, DateTime>{};
    for (final m in steps) {
      if (!inWindow(m.capturedAt)) continue;
      final key = dayKey(m.capturedAt);
      final prevAt = stepsCapturedAt[key];
      if (prevAt == null || m.capturedAt.isAfter(prevAt)) {
        stepsByDay[key] = m.value;
        stepsCapturedAt[key] = m.capturedAt;
      }
    }

    final kcalByDay = <String, double>{};
    final kcalCapturedAt = <String, DateTime>{};
    for (final m in energy) {
      if (!inWindow(m.capturedAt)) continue;
      final key = dayKey(m.capturedAt);
      final prevAt = kcalCapturedAt[key];
      if (prevAt == null || m.capturedAt.isAfter(prevAt)) {
        kcalByDay[key] = m.value;
        kcalCapturedAt[key] = m.capturedAt;
      }
    }

    final allDays = <String>{...stepsByDay.keys, ...kcalByDay.keys}.toList()
      ..sort();
    final days = <Map<String, Object?>>[];
    var stepTotal = 0.0;
    var stepDayCount = 0;
    var kcalTotal = 0.0;
    var kcalDayCount = 0;
    for (final d in allDays) {
      final steps = stepsByDay[d];
      final kcal = kcalByDay[d];
      if (steps != null) {
        stepTotal += steps;
        stepDayCount += 1;
      }
      if (kcal != null) {
        kcalTotal += kcal;
        kcalDayCount += 1;
      }
      days.add(<String, Object?>{
        'date': d,
        'steps': steps?.round(),
        'active_kcal': kcal == null ? null : _round(kcal),
      });
    }

    return <String, Object?>{
      'from': dayKey(fromInstant),
      'to': dayKey(now),
      'days': days,
      'summary': <String, Object?>{
        'total_steps': stepTotal.round(),
        'average_steps': stepDayCount == 0
            ? null
            : (stepTotal / stepDayCount).round(),
        'total_active_kcal': _round(kcalTotal),
        'average_active_kcal':
            kcalDayCount == 0 ? null : _round(kcalTotal / kcalDayCount),
        'step_day_count': stepDayCount,
        'kcal_day_count': kcalDayCount,
      },
      if (days.isEmpty)
        'note':
            'HealthOS 域尚无步数 / 主动消耗数据。建议用户在 Settings → Domains 启用 Health,'
            '然后从 HealthKit / Health Connect 导入。',
    };
  }

  static double _round(double v) => (v * 100).round() / 100.0;
}
