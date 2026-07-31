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
    required this.confidence,
    required this.coverage,
    required this.freshnessHours,
    required this.components,
  });

  /// Null when insufficient data.
  final int? score;

  /// One of: `rested`, `balanced`, `strained`, `insufficient_data`.
  final String verdict;

  /// Raw metric values that drove the score.
  final Map<String, Object?> inputs;

  /// `high`, `medium`, `low`, or `insufficient`.
  final String confidence;

  /// Fraction of the six supported inputs that contributed to the score.
  final double coverage;

  /// Age of the freshest recent input. Null when there is no recent input.
  final double? freshnessHours;

  /// Explainable per-input scores and recent/baseline sample counts.
  final List<Map<String, Object?>> components;

  bool get hasScore => score != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'score': score,
    'verdict': verdict,
    'inputs': inputs,
    'confidence': confidence,
    'coverage': coverage,
    'freshness_hours': freshnessHours,
    'components': components,
  };
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
    final sleepHoursBaseline = _avgSleepHours(sleep, baselineFrom, baselineTo);
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
      'avg_sleep_hours': sleepHoursRecent == null
          ? null
          : _round(sleepHoursRecent),
      'latest_rhr_bpm': rhrRecent == null ? null : _round(rhrRecent),
      'latest_vo2_max': vo2Recent == null ? null : _round(vo2Recent),
      'latest_body_battery': bbRecent == null ? null : _round(bbRecent),
      'latest_stress': stressRecent == null ? null : _round(stressRecent),
    };

    final haveBaseline =
        hrvBaselineN >= 5 ||
        sleepBaselineN >= 5 ||
        rhrBaselineN >= 5 ||
        vo2BaselineN >= 5 ||
        bbBaselineN >= 5 ||
        stressBaselineN >= 5;
    final haveRecent =
        hrvRecent != null ||
        sleepHoursRecent != null ||
        rhrRecent != null ||
        vo2Recent != null ||
        bbRecent != null ||
        stressRecent != null;

    final freshestAt = _freshestAt(
      <List<HealthMetric>>[hrv, sleep, rhr, vo2Max, bodyBattery, stress],
      recentFrom,
      t,
    );
    final freshnessHours = freshestAt == null
        ? null
        : t.difference(freshestAt).inMinutes / 60;

    if (!haveBaseline || !haveRecent) {
      return RecoveryResult(
        score: null,
        verdict: 'insufficient_data',
        inputs: inputs,
        confidence: 'insufficient',
        coverage: 0,
        freshnessHours: freshnessHours,
        components: const <Map<String, Object?>>[],
      );
    }

    // Per-component sub-scores in 0–100.
    final subScores = <double>[];
    final components = <Map<String, Object?>>[];

    void addComponent({
      required String key,
      required double score,
      required int recentSamples,
      required int baselineSamples,
      required double recentValue,
      double? baselineValue,
    }) {
      subScores.add(score);
      components.add(<String, Object?>{
        'metric': key,
        'score': _round(score),
        'recent_samples': recentSamples,
        'baseline_samples': baselineSamples,
        'recent_value': _round(recentValue),
        'baseline_value': baselineValue == null ? null : _round(baselineValue),
        'delta_pct': baselineValue == null || baselineValue == 0
            ? null
            : _round((recentValue - baselineValue) / baselineValue * 100),
        'weight': 1,
      });
    }

    if (hrvRecent != null && hrvBaseline != null && hrvBaseline > 0) {
      final ratio = (hrvRecent - hrvBaseline) / hrvBaseline;
      addComponent(
        key: 'hrv',
        score: _clamp(50 + ratio * 125, 0, 100),
        recentSamples: _countInWindow(hrv, recentFrom, t),
        baselineSamples: hrvBaselineN,
        recentValue: hrvRecent,
        baselineValue: hrvBaseline,
      );
    }
    if (rhrRecent != null && rhrBaseline != null && rhrBaseline > 0) {
      final ratio = (rhrRecent - rhrBaseline) / rhrBaseline;
      addComponent(
        key: 'rhr',
        score: _clamp(50 - ratio * 125, 0, 100),
        recentSamples: _countInWindow(rhr, recentFrom, t),
        baselineSamples: rhrBaselineN,
        recentValue: rhrRecent,
        baselineValue: rhrBaseline,
      );
    }
    if (sleepHoursRecent != null) {
      addComponent(
        key: 'sleep',
        score: _clamp(50 + (sleepHoursRecent - 7.0) * 20, 0, 100),
        recentSamples: _countInWindow(sleep, recentFrom, t),
        baselineSamples: sleepBaselineN,
        recentValue: sleepHoursRecent,
        baselineValue: sleepHoursBaseline,
      );
    }
    if (vo2Recent != null && vo2Baseline != null && vo2Baseline > 0) {
      final ratio = (vo2Recent - vo2Baseline) / vo2Baseline;
      addComponent(
        key: 'vo2_max',
        score: _clamp(50 + ratio * 125, 0, 100),
        recentSamples: _countInWindow(vo2Max, recentFrom, t),
        baselineSamples: vo2BaselineN,
        recentValue: vo2Recent,
        baselineValue: vo2Baseline,
      );
    }
    // Body Battery: higher is better (like HRV).
    if (bbRecent != null && bbBaseline != null && bbBaseline > 0) {
      final ratio = (bbRecent - bbBaseline) / bbBaseline;
      addComponent(
        key: 'body_battery',
        score: _clamp(50 + ratio * 125, 0, 100),
        recentSamples: _countInWindow(bodyBattery, recentFrom, t),
        baselineSamples: bbBaselineN,
        recentValue: bbRecent,
        baselineValue: bbBaseline,
      );
    }
    // Stress: lower is better (like RHR — inverted).
    if (stressRecent != null && stressBaseline != null && stressBaseline > 0) {
      final ratio = (stressRecent - stressBaseline) / stressBaseline;
      addComponent(
        key: 'stress',
        score: _clamp(50 - ratio * 125, 0, 100),
        recentSamples: _countInWindow(stress, recentFrom, t),
        baselineSamples: stressBaselineN,
        recentValue: stressRecent,
        baselineValue: stressBaseline,
      );
    }

    if (subScores.isEmpty) {
      return RecoveryResult(
        score: null,
        verdict: 'insufficient_data',
        inputs: inputs,
        confidence: 'insufficient',
        coverage: 0,
        freshnessHours: freshnessHours,
        components: const <Map<String, Object?>>[],
      );
    }

    final avg = subScores.reduce((a, b) => a + b) / subScores.length;
    final rounded = avg.round();
    final coverage = subScores.length / 6;
    final confidence = switch ((coverage, freshnessHours)) {
      (>= 0.66, final double hours) when hours <= 36 => 'high',
      (>= 0.33, final double hours) when hours <= 72 => 'medium',
      _ => 'low',
    };
    final verdict = rounded < 40
        ? 'strained'
        : rounded < 70
        ? 'balanced'
        : 'rested';

    return RecoveryResult(
      score: rounded,
      verdict: verdict,
      inputs: inputs,
      confidence: confidence,
      coverage: _round(coverage),
      freshnessHours: freshnessHours == null ? null : _round(freshnessHours),
      components: List<Map<String, Object?>>.unmodifiable(components),
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

  static DateTime? _freshestAt(
    List<List<HealthMetric>> groups,
    DateTime from,
    DateTime to,
  ) {
    DateTime? latest;
    for (final rows in groups) {
      for (final metric in rows) {
        if (metric.capturedAt.isBefore(from) || metric.capturedAt.isAfter(to)) {
          continue;
        }
        if (latest == null || metric.capturedAt.isAfter(latest)) {
          latest = metric.capturedAt;
        }
      }
    }
    return latest;
  }

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  static double _round(double v) => (v * 100).round() / 100.0;
}
