/// `get_stress_trend` — HealthOS device tool.
///
/// Read-only AI surface over `stress_daily` rows. Returns the
/// chronological series + first-half / second-half delta, mirroring
/// the `get_hrv_trend` shape so the model can compare patterns.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class GetStressTrendTool implements DeviceTool {
  const GetStressTrendTool();

  @override
  String get name => 'get_stress_trend';

  @override
  String get description =>
      '返回每日平均压力水平 (Garmin stress) 在指定窗口 (默认 30 天) 内的'
      '序列 + 前半/后半均值对比。数据来自 health_metrics 表的 stress_daily 类型。'
      '适合场景:"我最近压力大吗"/"压力在升高还是降低"。'
      '解读约定:压力值 0-100,↑ 表示压力增大;短期波动不解读为趋势。'
      '当无数据时返回空 points + note。';

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
      kind: HealthMetricKind.stressDaily,
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
    final inWindow = rows
        .where((m) =>
            !m.capturedAt.isBefore(fromInstant) && !m.capturedAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    final points = <Map<String, Object?>>[];
    for (final m in inWindow) {
      points.add(<String, Object?>{
        'date': m.capturedAt.toUtc().toIso8601String().substring(0, 10),
        'stress_level': _round(m.value),
      });
    }

    Map<String, Object?>? summary;
    if (points.length >= 4) {
      final mid = points.length ~/ 2;
      final firstHalf = inWindow.sublist(0, mid).map((m) => m.value);
      final secondHalf = inWindow.sublist(mid).map((m) => m.value);
      final avgFirst = _mean(firstHalf);
      final avgSecond = _mean(secondHalf);
      final delta = avgFirst == 0
          ? null
          : ((avgSecond - avgFirst) / avgFirst) * 100.0;
      summary = <String, Object?>{
        'latest': _round(inWindow.last.value),
        'average': _round(_mean(inWindow.map((m) => m.value))),
        'first_half_average': _round(avgFirst),
        'second_half_average': _round(avgSecond),
        'delta_pct': delta == null ? null : _round(delta),
      };
    } else if (points.isNotEmpty) {
      summary = <String, Object?>{
        'latest': _round(inWindow.last.value),
        'average': _round(_mean(inWindow.map((m) => m.value))),
      };
    }

    return <String, Object?>{
      'window_days': windowDays,
      'from': fromInstant.toIso8601String().substring(0, 10),
      'to': now.toIso8601String().substring(0, 10),
      'points': points,
      'summary': ?summary,
      if (points.isEmpty)
        'note': 'No stress data yet. Connect a Garmin device in HealthOS.',
      if (points.isNotEmpty && points.length < 4)
        'note': 'Fewer than 4 samples in window — trend (delta_pct) is not '
            'meaningful. Collect 1-2 weeks of data first.',
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
