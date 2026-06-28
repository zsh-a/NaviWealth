/// `get_activity_summary` — HealthOS device tool
/// (`docs/domains/healthos-domain.md` §4, D-2.4).
///
/// Read-only AI surface that joins `steps_daily` + `active_energy_daily`
/// per calendar day. Returns per-day records plus totals / averages
/// over the requested window.
library;

import 'dart:convert';

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
      '返回最近 N 天的每日活动汇总:步数 + 全天步行/跑步距离 (walking_distance_km) + '
      '主动消耗卡路里 (active energy) + workout 汇总 (条数 / 总时长 / workout 距离)。'
      '数据来自端侧 `health_metrics` 表的 `steps_daily` / `distance_walking_running_daily` / '
      '`active_energy_daily` / `workout_session`,按日期 join (workout 按 capturedAt 落到所在 UTC 日)。'
      'walking_distance_km 是全天步行+跑步距离(包含通勤/散步),workout_distance_km 只算运动 session。'
      '适合场景:"最近一周走了多少步" / "周末和工作日的活动差异" / "今天步数够不够" / '
      '"上周训练多少次" / "这周走了多少公里"。'
      '当 HealthOS 未启用或缺少某一类数据时,对应字段会留为 null;'
      '完全空时返回空 `days` + `note`,建议用户启用 Health。';

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

    // A heavy user might log 3–5 workouts/day; pull a generous buffer
    // so we don't crop the window short. listByKinds orders newest
    // first per kind, and the shaper filters by window.
    final data = await repo.listByKinds(
      ownerUserId: ownerUserId,
      kinds: const <HealthMetricKind>{
        HealthMetricKind.stepsDaily,
        HealthMetricKind.activeEnergyDaily,
        HealthMetricKind.distanceWalkingRunningDaily,
        HealthMetricKind.workoutSession,
      },
      limit: daysBack * 5 + 10,
    );
    final now = DateTime.now().toUtc();
    return shape(
      steps: data[HealthMetricKind.stepsDaily] ?? const <HealthMetric>[],
      energy:
          data[HealthMetricKind.activeEnergyDaily] ?? const <HealthMetric>[],
      workouts: data[HealthMetricKind.workoutSession] ?? const <HealthMetric>[],
      walkingDistance:
          data[HealthMetricKind.distanceWalkingRunningDaily] ??
          const <HealthMetric>[],
      daysBack: daysBack,
      now: now,
    );
  }

  /// Pure shaper — exposed for unit tests.
  static Map<String, Object?> shape({
    required List<HealthMetric> steps,
    required List<HealthMetric> energy,
    List<HealthMetric> workouts = const <HealthMetric>[],
    List<HealthMetric> walkingDistance = const <HealthMetric>[],
    required int daysBack,
    required DateTime now,
  }) {
    final fromInstant = now.subtract(Duration(days: daysBack));

    // Bucket by ISO date (YYYY-MM-DD). Within a day, latest reading wins
    // (later sync overrides an earlier partial number).
    String dayKey(DateTime d) => d.toUtc().toIso8601String().substring(0, 10);
    bool inWindow(DateTime d) => !d.isBefore(fromInstant) && !d.isAfter(now);

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

    // Walking + running distance (meters). Same latest-wins-per-day rule
    // as steps/energy; the platform writes one daily aggregate row.
    final walkMetersByDay = <String, double>{};
    final walkCapturedAt = <String, DateTime>{};
    for (final m in walkingDistance) {
      if (!inWindow(m.capturedAt)) continue;
      final key = dayKey(m.capturedAt);
      final prevAt = walkCapturedAt[key];
      if (prevAt == null || m.capturedAt.isAfter(prevAt)) {
        walkMetersByDay[key] = m.value;
        walkCapturedAt[key] = m.capturedAt;
      }
    }

    // Workouts: aggregate per day (sum count / duration / distance from
    // payload). Unlike steps/energy daily rollups, each session is its
    // own row; multiple per day is normal so we keep all of them.
    final workoutSecondsByDay = <String, double>{};
    final workoutCountByDay = <String, int>{};
    final workoutDistanceByDay = <String, double>{};
    var workoutTotalSeconds = 0.0;
    var workoutTotalCount = 0;
    var workoutTotalDistance = 0.0;
    for (final m in workouts) {
      if (!inWindow(m.capturedAt)) continue;
      if (m.kind != HealthMetricKind.workoutSession) continue;
      final key = dayKey(m.capturedAt);
      final seconds = m.value; // duration seconds
      workoutSecondsByDay.update(
        key,
        (v) => v + seconds,
        ifAbsent: () => seconds,
      );
      workoutCountByDay.update(key, (v) => v + 1, ifAbsent: () => 1);
      workoutTotalSeconds += seconds;
      workoutTotalCount += 1;
      final distance = _distanceMetersFromPayload(m.payloadJson);
      if (distance != null) {
        workoutDistanceByDay.update(
          key,
          (v) => v + distance,
          ifAbsent: () => distance,
        );
        workoutTotalDistance += distance;
      }
    }

    final allDays = <String>{
      ...stepsByDay.keys,
      ...kcalByDay.keys,
      ...walkMetersByDay.keys,
      ...workoutCountByDay.keys,
    }.toList()..sort();
    final days = <Map<String, Object?>>[];
    var stepTotal = 0.0;
    var stepDayCount = 0;
    var kcalTotal = 0.0;
    var kcalDayCount = 0;
    var walkMetersTotal = 0.0;
    var walkDayCount = 0;
    for (final d in allDays) {
      final steps = stepsByDay[d];
      final kcal = kcalByDay[d];
      final walkMeters = walkMetersByDay[d];
      if (steps != null) {
        stepTotal += steps;
        stepDayCount += 1;
      }
      if (kcal != null) {
        kcalTotal += kcal;
        kcalDayCount += 1;
      }
      if (walkMeters != null) {
        walkMetersTotal += walkMeters;
        walkDayCount += 1;
      }
      final workoutCount = workoutCountByDay[d];
      final workoutSeconds = workoutSecondsByDay[d];
      final workoutDistance = workoutDistanceByDay[d];
      days.add(<String, Object?>{
        'date': d,
        'steps': steps?.round(),
        'walking_distance_km': walkMeters == null
            ? null
            : _round(walkMeters / 1000.0),
        'active_kcal': kcal == null ? null : _round(kcal),
        'workout_count': workoutCount,
        'workout_minutes': workoutSeconds == null
            ? null
            : _round(workoutSeconds / 60.0),
        'workout_distance_km': workoutDistance == null
            ? null
            : _round(workoutDistance / 1000.0),
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
        'total_walking_distance_km': walkDayCount == 0
            ? null
            : _round(walkMetersTotal / 1000.0),
        'average_walking_distance_km': walkDayCount == 0
            ? null
            : _round((walkMetersTotal / walkDayCount) / 1000.0),
        'walking_day_count': walkDayCount,
        'total_active_kcal': _round(kcalTotal),
        'average_active_kcal': kcalDayCount == 0
            ? null
            : _round(kcalTotal / kcalDayCount),
        'step_day_count': stepDayCount,
        'kcal_day_count': kcalDayCount,
        'workout_count': workoutTotalCount,
        'workout_total_minutes': workoutTotalCount == 0
            ? 0
            : _round(workoutTotalSeconds / 60.0),
        'workout_total_distance_km': workoutTotalDistance == 0
            ? 0
            : _round(workoutTotalDistance / 1000.0),
      },
      if (days.isEmpty)
        'note':
            'HealthOS 域尚无活动数据。建议用户在 Settings → Domains 启用 Health,'
            '然后从 HealthKit / Health Connect 导入。',
    };
  }

  /// Returns the distance the platform recorded for a workout, in
  /// meters, or `null` if the payload is missing / malformed / not a
  /// distance activity. Soft-fails on every error path — the AI tool
  /// shouldn't blow up the response over a single weird payload row.
  static double? _distanceMetersFromPayload(String? payloadJson) {
    if (payloadJson == null || payloadJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return null;
      final v = decoded['total_distance_meters'];
      if (v is num) return v.toDouble();
      return null;
    } on FormatException {
      return null;
    }
  }

  static double _round(double v) => (v * 100).round() / 100.0;
}
