part of 'health_metric_memory_indexer.dart';

mixin _HealthMetricMemoryFormatting {
  double _average(Iterable<double> values) {
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      sum += value;
      count++;
    }
    return count == 0 ? 0.0 : sum / count;
  }

  double _secondsToHours(double value, String unit) {
    return switch (unit) {
      's' => value / 3600.0,
      'min' => value / 60.0,
      'h' => value,
      _ => value / 3600.0,
    };
  }

  double _round(double v) => (v * 100).round() / 100.0;
}
