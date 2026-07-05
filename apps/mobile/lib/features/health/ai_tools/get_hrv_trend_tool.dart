/// `get_hrv_trend` — HealthOS device tool
/// (`docs/domains/healthos-domain.md` §4, D-2.4).
///
/// Read-only AI surface over the `hrv_daily` rows. Returns the
/// chronological series + a first-half / second-half delta that the
/// model can use to phrase "HRV is trending up vs last fortnight"
/// without doing math itself.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class GetHrvTrendTool implements DeviceTool {
  const GetHrvTrendTool();

  @override
  String get name => 'get_hrv_trend';

  @override
  String get description =>
      '返回 HRV (心率变异性) 在指定窗口 (默认 30 天,可选 90 天) 内的每日序列 + '
      '前半 / 后半均值对比的趋势百分比。数据来自端侧 `health_metrics` 表的 '
      '`hrv_daily` 类型 (单位 ms)。'
      '适合场景:"我最近恢复状态怎么样" / "HRV 在变好还是变差"。'
      '解读约定:HRV ↑ 通常对应恢复改善;短期单点波动不解读为趋势。'
      '当 HealthOS 未启用或尚未导入 HRV 数据时,返回空 `points` + `note`,'
      '此时建议用户在 Settings → Domains 启用 Health 并连接数据源。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'window_days': {
        'type': 'integer',
        'enum': [7, 14, 30, 60, 90],
        'default': 30,
        'description': '窗口天数。允许 7 / 14 / 30 / 60 / 90,默认 30。',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final windowDays = _normalizeWindow(input['window_days']);
    final repo = await ctx.ref.read(healthMetricRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final rows = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.hrvDaily,
      limit: windowDays + 10,
    );
    final now = DateTime.now().toUtc();
    return shape(rows, windowDays: windowDays, now: now);
  }

  static int _normalizeWindow(Object? raw) {
    if (raw is num) {
      final v = raw.toInt();
      const allowed = [7, 14, 30, 60, 90];
      return allowed.contains(v) ? v : 30;
    }
    return 30;
  }

  /// Pure shaper — exposed for unit tests.
  static Map<String, Object?> shape(
    List<HealthMetric> rows, {
    required int windowDays,
    required DateTime now,
  }) {
    final fromInstant = now.subtract(Duration(days: windowDays));
    // Window-filter, then sort oldest-first so the JSON `points`
    // array reads chronologically (the repo returns newest-first).
    final inWindow =
        rows
            .where(
              (m) =>
                  !m.capturedAt.isBefore(fromInstant) &&
                  !m.capturedAt.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    final points = <Map<String, Object?>>[];
    for (final m in inWindow) {
      points.add(<String, Object?>{
        'date': m.capturedAt.toUtc().toIso8601String().substring(0, 10),
        'hrv_ms': _round(m.value),
      });
    }

    Map<String, Object?>? summary;
    if (points.length >= 4) {
      // Split chronological halves; require ≥ 2 points each side so the
      // delta isn't dominated by a single noisy reading.
      final mid = points.length ~/ 2;
      final firstHalf = inWindow.sublist(0, mid).map((m) => m.value);
      final secondHalf = inWindow.sublist(mid).map((m) => m.value);
      final avgFirst = _mean(firstHalf);
      final avgSecond = _mean(secondHalf);
      final delta = avgFirst == 0
          ? null
          : ((avgSecond - avgFirst) / avgFirst) * 100.0;
      summary = <String, Object?>{
        'latest_ms': _round(inWindow.last.value),
        'average_ms': _round(_mean(inWindow.map((m) => m.value))),
        'first_half_average_ms': _round(avgFirst),
        'second_half_average_ms': _round(avgSecond),
        'delta_pct': delta == null ? null : _round(delta),
      };
    } else if (points.isNotEmpty) {
      summary = <String, Object?>{
        'latest_ms': _round(inWindow.last.value),
        'average_ms': _round(_mean(inWindow.map((m) => m.value))),
        'first_half_average_ms': null,
        'second_half_average_ms': null,
        'delta_pct': null,
      };
    }

    return <String, Object?>{
      'window_days': windowDays,
      'from': fromInstant.toIso8601String().substring(0, 10),
      'to': now.toIso8601String().substring(0, 10),
      'points': points,
      'summary': ?summary,
      if (points.isEmpty)
        'note':
            'HealthOS 域尚无 HRV 数据。建议用户在 Settings → Domains 启用 Health,'
            '然后从 HealthKit / Health Connect 导入。',
      if (points.isNotEmpty && points.length < 4)
        'note':
            '当前窗口内 HRV 样本不足 4 条,趋势 (delta_pct) 不可解读。建议至少'
            '收集 1-2 周后再问"HRV 趋势如何"。',
    };
  }

  static double _mean(Iterable<double> xs) {
    var sum = 0.0;
    var n = 0;
    for (final x in xs) {
      sum += x;
      n += 1;
    }
    return n == 0 ? 0.0 : sum / n;
  }

  static double _round(double v) => (v * 100).round() / 100.0;
}
