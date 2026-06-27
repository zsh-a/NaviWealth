/// Hybrid memory scorer (`docs/architecture/lifeos-shell.md` §6, D-1.7b).
///
/// Combines five orthogonal signals into one final ranking score.
/// Weights come from the user's brief in the LifeOS Memory design
/// discussion:
///
/// ```
/// score = 0.35*semantic + 0.25*importance + 0.20*entity
///       + 0.10*recency  + 0.10*confidence
/// ```
///
/// All five inputs are clamped to `[0, 1]`. Missing semantic similarity
/// (no embedding / no query) is treated as `0` so the other signals
/// still rank.
library;

import 'dart:math' as math;

const double kWeightSemantic = 0.35;
const double kWeightImportance = 0.25;
const double kWeightEntity = 0.20;
const double kWeightRecency = 0.10;
const double kWeightConfidence = 0.10;

double hybridScore({
  required double? semanticSim,
  required double importance,
  required double entityOverlap,
  required double recency,
  required double confidence,
}) {
  final sem = (semanticSim ?? 0.0).clamp(0.0, 1.0);
  final imp = importance.clamp(0.0, 1.0);
  final ent = entityOverlap.clamp(0.0, 1.0);
  final rec = recency.clamp(0.0, 1.0);
  final con = confidence.clamp(0.0, 1.0);
  return kWeightSemantic * sem +
      kWeightImportance * imp +
      kWeightEntity * ent +
      kWeightRecency * rec +
      kWeightConfidence * con;
}

/// Jaccard overlap between two sets of entity tags. `0` when either
/// side is empty.
double entityOverlap(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  if (inter == 0) return 0;
  final union = a.union(b).length;
  return inter / union;
}

/// Exponential decay: 1.0 at `now`, `0.5` at [halfLife] old, → 0 as
/// age grows. Used by the scorer's recency term.
double recencyScore(DateTime ts, DateTime now, {Duration? halfLife}) {
  final hl = halfLife ?? const Duration(days: 30);
  final ageMs = now.difference(ts).inMilliseconds.toDouble();
  if (ageMs <= 0) return 1.0;
  final hlMs = hl.inMilliseconds.toDouble();
  if (hlMs <= 0) return 1.0;
  // 0.5 ^ (age / halfLife)
  return math.pow(0.5, ageMs / hlMs).toDouble();
}
