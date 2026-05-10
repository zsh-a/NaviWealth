import 'chart_series.dart';

/// Default upper bound after which charts auto-downsample. ~500 px wide
/// charts can't usefully render more than ~1 sample per pixel; rendering
/// 1800+ points at full density burns CPU on a value the eye can't see.
const int kDefaultDownsampleTarget = 500;

/// Largest-Triangle-Three-Buckets (LTTB) downsampling.
///
/// O(n) algorithm that preserves visual peaks/troughs much better than naive
/// stride sampling. Reference: Sveinn Steinarsson, "Downsampling Time Series
/// for Visual Representation" (2013).
///
/// - First and last points are always kept.
/// - For each of the remaining `targetCount - 2` buckets we pick the point
///   that forms the largest triangle with the previous selected point and
///   the average point of the next bucket.
/// - Caller-supplied `meta` is preserved on the chosen original points; no
///   meta synthesis happens, so drill-down callbacks receive the original
///   domain object intact.
List<ChartPoint> downsampleLttb(List<ChartPoint> points, int targetCount) {
  if (targetCount >= points.length || targetCount < 3) {
    return points;
  }
  final n = points.length;
  final sampled = <ChartPoint>[points.first];

  // Bucket size for the n-2 middle points.
  final bucketSize = (n - 2) / (targetCount - 2);

  int aIndex = 0;
  for (int i = 0; i < targetCount - 2; i++) {
    // Compute average point of the next bucket (a + 1 worth of buckets ahead).
    final nextBucketStart = ((i + 1) * bucketSize).floor() + 1;
    final nextBucketEnd = ((i + 2) * bucketSize).floor() + 1;
    final nextEnd = nextBucketEnd < n ? nextBucketEnd : n;

    double avgX = 0;
    double avgY = 0;
    final avgRange = nextEnd - nextBucketStart;
    if (avgRange == 0) continue;
    for (int j = nextBucketStart; j < nextEnd; j++) {
      avgX += points[j].x;
      avgY += points[j].y;
    }
    avgX /= avgRange;
    avgY /= avgRange;

    // Inspect the current bucket and pick the point that forms the largest
    // triangle with `sampled.last` and (avgX, avgY).
    final rangeStart = (i * bucketSize).floor() + 1;
    final rangeEnd = ((i + 1) * bucketSize).floor() + 1;
    final pointAX = points[aIndex].x;
    final pointAY = points[aIndex].y;
    double maxArea = -1;
    int maxAreaIndex = rangeStart;
    for (int j = rangeStart; j < rangeEnd && j < n; j++) {
      final area =
          ((pointAX - avgX) * (points[j].y - pointAY) -
                  (pointAX - points[j].x) * (avgY - pointAY))
              .abs() *
          0.5;
      if (area > maxArea) {
        maxArea = area;
        maxAreaIndex = j;
      }
    }
    sampled.add(points[maxAreaIndex]);
    aIndex = maxAreaIndex;
  }

  sampled.add(points.last);
  return sampled;
}

/// Convenience: applies [downsampleLttb] only when above [target].
List<ChartPoint> maybeDownsample(
  List<ChartPoint> points, {
  int target = kDefaultDownsampleTarget,
  bool enabled = true,
}) {
  if (!enabled || points.length <= target) return points;
  return downsampleLttb(points, target);
}
