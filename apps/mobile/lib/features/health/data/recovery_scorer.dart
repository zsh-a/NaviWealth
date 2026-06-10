/// Recovery scoring service — shared between AI tools, Today page, and Plan.
///
/// Computes a composite recovery score (0–100) from HRV, sleep, RHR,
/// VO2max, Body Battery, and Stress against a rolling baseline. The
/// scoring math lives here so the AI tool, `recoverySignalProvider`,
/// and Plan page all produce identical results.
///
/// This is a pure service — no Riverpod, no DB access. Callers fetch
/// the raw `HealthMetric` lists and pass them in.
library;

import '../domain/health_metric.dart';

/// Recovery scoring result.
class RecoveryResult {
  const RecoveryResult({
    required this.score,
    required this.verdict,
    required this.inputs,
  });

  /// Null when insufficient data.
  final int? score;

  /// One of: `rested`, `balanced`, `strained`, `insufficient_data`.
  final String verdict;

  /// Raw metric values that drove the score.
  final Map<String, Object?> inputs;

  bool get hasScore => score != null;
}

/// Pure recovery scorer — no side effects, no DB.
class RecoveryScorer {
  const RecoveryScorer();

  /// Compute recovery from raw metric lists.
  ///
  /// All lists are newest-first (repo default). The scorer windows them
  /// internally.
  RecoveryResult score({
    required List<HealthMetric> hrv,
    required List<HealthMetric> sleep,
    required List<HealthMetric> rhr,
    List<HealthMetric> vo2Max = const <HealthMetric>[],
    List<HealthMetric> bodyBattery = const <HealthMetric>[],
    List<HealthMetric> stress = const <HealthMetric>[],
    DateTime? now,
  }) {
    final t = now ?? DateTime.now().toUtc();

    // Recent = last 7 days; baseline = 7–28 days ago, excluding recent.
    final recentFrom = t.subtract(const Duration(days: 7));
    final baselineFrom = t.subtract(const Duration(days: 28));
    final baselineTo = recentFrom;

    final hrvRecent = _avgInWindow(hrv, recentFrom, t);
    final hrvBaseline = _avgInWindow(hrv, baselineFrom, baselineTo);
    final hrvBaselineN = _countInWindow(hrv, baselineFrom, baselineTo);

    final rhrRecent = _avgInWindow(rhr, recentFrom, t);
    final rhrBaseline = _avgInWindow(rhr, baselineFrom, baselineTo);
    final rhrBaselineN = _countInWindow(rhr, baselineFrom, baselineTo);

    final sleepHoursRecent = _avgSleepHours(sleep, recentFrom, t);
    final sleepBaselineN = _countInWindow(sleep, baselineFrom, baselineTo);

    final vo2Recent = _avgInWindow(vo2Max, recentFrom, t);
    final vo2Baseline = _avgInWindow(vo2Max, baselineFrom, baselineTo);
    final vo2BaselineN = _countInWindow(vo2Max, baselineFrom, baselineTo);

    final bbRecent = _avgInWindow(bodyBattery, recentFrom, t);
    final bbBaseline = _avgInWindow(bodyBattery, baselineFrom, baselineTo);
    final bbBaselineN = _countInWindow(bodyBattery, baselineFrom, baselineTo);

    final stressRecent = _avgInWindow(stress, recentFrom, t);
    final stressBaseline = _avgInWindow(stress, baselineFrom, baselineTo);
    final stressBaselineN = _countInWindow(stress, baselineFrom, baselineTo);

    final inputs = <String, Object?>{
      'latest_hrv_ms': hrvRecent == null ? null : _round(hrvRecent),
      'avg_sleep_hours':
          sleepHoursRecent == null ? null : _round(sleepHoursRecent),
      'latest_rhr_bpm': rhrRecent == null ? null : _round(rhrRecent),
      'latest_vo2_max': vo2Recent == null ? null : _round(vo2Recent),
      'latest_body_battery': bbRecent == null ? null : _round(bbRecent),
      'latest_stress': stressRecent == null ? null : _round(stressRecent),
    };

    final haveBaseline = hrvBaselineN >= 5 ||
        sleepBaselineN >= 5 ||
        rhrBaselineN >= 5 ||
        vo2BaselineN >= 5 ||
        bbBaselineN >= 5 ||
        stressBaselineN >= 5;
    final haveRecent = hrvRecent != null ||
        sleepHoursRecent != null ||
        rhrRecent != null ||
        vo2Recent != null ||
        bbRecent != null ||
        stressRecent != null;

    if (!haveBaseline || !haveRecent) {
      return RecoveryResult(
        score: null,
        verdict: 'insufficient_data',
        inputs: inputs,
      );
    }

    // Per-component sub-scores in 0–100.
    final subScores = <double>[];

    if (hrvRecent != null && hrvBaseline != null && hrvBaseline > 0) {
      final ratio = (hrvRecent - hrvBaseline) / hrvBaseline;
      subScores.add(_clamp(50 + ratio * 125, 0, 100));
    }
    if (rhrRecent != null && rhrBaseline != null && rhrBaseline > 0) {
      final ratio = (rhrRecent - rhrBaseline) / rhrBaseline;
      subScores.add(_clamp(50 - ratio * 125, 0, 100));
    }
    if (sleepHoursRecent != null) {
      subScores.add(_clamp(50 + (sleepHoursRecent - 7.0) * 20, 0, 100));
    }
    if (vo2Recent != null && vo2Baseline != null && vo2Baseline > 0) {
      final ratio = (vo2Recent - vo2Baseline) / vo2Baseline;
      subScores.add(_clamp(50 + ratio * 125, 0, 100));
    }
    // Body Battery: higher is better (like HRV).
    if (bbRecent != null && bbBaseline != null && bbBaseline > 0) {
      final ratio = (bbRecent - bbBaseline) / bbBaseline;
      subScores.add(_clamp(50 + ratio * 125, 0, 100));
    }
    // Stress: lower is better (like RHR — inverted).
    if (stressRecent != null && stressBaseline != null && stressBaseline > 0) {
      final ratio = (stressRecent - stressBaseline) / stressBaseline;
      subScores.add(_clamp(50 - ratio * 125, 0, 100));
    }

    if (subScores.isEmpty) {
      return RecoveryResult(
        score: null,
        verdict: 'insufficient_data',
        inputs: inputs,
      );
    }

    final avg = subScores.reduce((a, b) => a + b) / subScores.length;
    final rounded = avg.round();
    final verdict = rounded < 40
        ? 'strained'
        : rounded < 70
            ? 'balanced'
            : 'rested';

    return RecoveryResult(
      score: rounded,
      verdict: verdict,
      inputs: inputs,
    );
  }

  // ---------------------------------------------------------------------------
  // Window helpers
  // ---------------------------------------------------------------------------

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
