/// `get_recovery_signal` — HealthOS device tool
/// (`docs/healthos-domain.md` §4, D-2.4).
///
/// Composite recovery score (0–100) blending HRV, sleep, and RHR vs a
/// rolling baseline. The model uses it for "should I push hard today /
/// take it easy" prompts. Verdict is one of:
///
///   - `insufficient_data` — fewer than 5 baseline days OR no current reading
///   - `strained`         — score < 40
///   - `balanced`         — 40 ≤ score < 70
///   - `rested`           — score ≥ 70
///
/// The raw inputs are also returned so the model can phrase nuances
/// ("HRV is fine but sleep was short") instead of just quoting the
/// score.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class GetRecoverySignalTool implements DeviceTool {
  const GetRecoverySignalTool();

  @override
  String get name => 'get_recovery_signal';

  @override
  String get description =>
      '返回综合恢复信号 (0–100 分) + 等级 (rested / balanced / strained / '
      'insufficient_data) + 三个原始输入 (最近 HRV / 最近平均睡眠时长 / 最近 RHR)。'
      '算法:取过去 7 天 (recent) 和过去 28 天 (baseline) 的 HRV / sleep / RHR 均值,'
      '每项按 recent vs baseline 偏离度评分 (HRV ↑ 加分, RHR ↑ 扣分, 睡眠 ≥ 7h 加分),'
      '三项算术平均后裁剪到 0–100。'
      '基线 < 5 天数据时返回 insufficient_data,模型应回避"推 / 减"建议。'
      '适合场景:"今天该不该重训"/"我恢复怎么样"/"我状态可以做高强度吗"。'
      '不是医学诊断,仅供日常作息判断。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(healthMetricRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final hrv = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.hrvDaily,
      limit: 35,
    );
    final sleep = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.sleepSession,
      limit: 50,
    );
    final rhr = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.rhrDaily,
      limit: 35,
    );

    final now = DateTime.now().toUtc();
    return shape(hrv: hrv, sleep: sleep, rhr: rhr, now: now);
  }

  /// Pure shaper — exposed for unit tests so the scoring math runs
  /// without a Drift database.
  static Map<String, Object?> shape({
    required List<HealthMetric> hrv,
    required List<HealthMetric> sleep,
    required List<HealthMetric> rhr,
    required DateTime now,
  }) {
    // Recent = last 7 days; baseline = 7–28 days ago, **excluding**
    // recent so a clear improvement isn't diluted by the very days
    // we're scoring.
    final recentFrom = now.subtract(const Duration(days: 7));
    final baselineFrom = now.subtract(const Duration(days: 28));
    final baselineTo = recentFrom;

    final hrvRecent = _avgInWindow(hrv, recentFrom, now);
    final hrvBaseline = _avgInWindow(hrv, baselineFrom, baselineTo);
    final hrvBaselineN = _countInWindow(hrv, baselineFrom, baselineTo);

    final rhrRecent = _avgInWindow(rhr, recentFrom, now);
    final rhrBaseline = _avgInWindow(rhr, baselineFrom, baselineTo);
    final rhrBaselineN = _countInWindow(rhr, baselineFrom, baselineTo);

    final sleepHoursRecent = _avgSleepHours(sleep, recentFrom, now);
    // Baseline sleep is unused in the current scoring (sleep is anchored
    // to an absolute 7 h target, not a personal baseline) but the count
    // still counts toward "do we have enough history" gating.
    final sleepBaselineN =
        _countInWindow(sleep, baselineFrom, baselineTo);

    final inputs = <String, Object?>{
      'latest_hrv_ms': hrvRecent == null ? null : _round(hrvRecent),
      'avg_sleep_hours': sleepHoursRecent == null
          ? null
          : _round(sleepHoursRecent),
      'latest_rhr_bpm': rhrRecent == null ? null : _round(rhrRecent),
    };

    final haveBaseline =
        hrvBaselineN >= 5 || sleepBaselineN >= 5 || rhrBaselineN >= 5;
    final haveRecent =
        hrvRecent != null || sleepHoursRecent != null || rhrRecent != null;

    if (!haveBaseline || !haveRecent) {
      return <String, Object?>{
        'score': null,
        'verdict': 'insufficient_data',
        'inputs': inputs,
        'note':
            'Health 数据不足以判定恢复:需要至少 5 天基线 + 最近 7 天的 HRV / 睡眠 / RHR 任一信号。',
      };
    }

    // Per-component sub-scores in 0–100. Each is centred on its
    // baseline; recent values better than baseline raise the score.
    final subScores = <double>[];

    if (hrvRecent != null && hrvBaseline != null && hrvBaseline > 0) {
      // HRV ↑ is good. ±20% maps to ±25 points.
      final ratio = (hrvRecent - hrvBaseline) / hrvBaseline;
      subScores.add(_clamp(50 + ratio * 125, 0, 100));
    }
    if (rhrRecent != null && rhrBaseline != null && rhrBaseline > 0) {
      // RHR ↑ is bad. Same scale, flipped sign.
      final ratio = (rhrRecent - rhrBaseline) / rhrBaseline;
      subScores.add(_clamp(50 - ratio * 125, 0, 100));
    }
    if (sleepHoursRecent != null) {
      // Sleep: 7 h is the neutral anchor; below 6 or above 9 saturates.
      // Score = 50 + (hours - 7) * 20 → 7h → 50, 8h → 70, 6h → 30.
      subScores.add(_clamp(50 + (sleepHoursRecent - 7.0) * 20, 0, 100));
    }

    if (subScores.isEmpty) {
      return <String, Object?>{
        'score': null,
        'verdict': 'insufficient_data',
        'inputs': inputs,
        'note': '基线齐备,但最近 7 天没有任何 HRV / 睡眠 / RHR 读数。',
      };
    }

    final score = subScores.reduce((a, b) => a + b) / subScores.length;
    final rounded = score.round();
    final verdict = rounded < 40
        ? 'strained'
        : rounded < 70
            ? 'balanced'
            : 'rested';

    return <String, Object?>{
      'score': rounded,
      'verdict': verdict,
      'inputs': inputs,
    };
  }

  static double? _avgInWindow(
    List<HealthMetric> rows,
    DateTime from,
    DateTime to,
  ) {
    var sum = 0.0;
    var n = 0;
    for (final m in rows) {
      if (m.capturedAt.isBefore(from) || m.capturedAt.isAfter(to)) continue;
      sum += m.value;
      n += 1;
    }
    return n == 0 ? null : sum / n;
  }

  static int _countInWindow(
    List<HealthMetric> rows,
    DateTime from,
    DateTime to,
  ) {
    var n = 0;
    for (final m in rows) {
      if (m.capturedAt.isBefore(from) || m.capturedAt.isAfter(to)) continue;
      n += 1;
    }
    return n;
  }

  /// Sleep rows store duration in `value` with `unit` ∈ {`s`, `min`, `h`}.
  /// We average duration in hours per session.
  static double? _avgSleepHours(
    List<HealthMetric> sessions,
    DateTime from,
    DateTime to,
  ) {
    var sumHours = 0.0;
    var n = 0;
    for (final m in sessions) {
      if (m.capturedAt.isBefore(from) || m.capturedAt.isAfter(to)) continue;
      sumHours += switch (m.unit) {
        's' => m.value / 3600.0,
        'min' => m.value / 60.0,
        'h' => m.value,
        _ => m.value / 3600.0,
      };
      n += 1;
    }
    return n == 0 ? null : sumHours / n;
  }

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  static double _round(double v) => (v * 100).round() / 100.0;
}
