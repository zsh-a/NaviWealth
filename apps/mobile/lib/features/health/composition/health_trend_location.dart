import '../domain/health_metric_kind.dart';
import 'health_route_paths.dart';

/// URL is the only persisted navigation state for Health analytics.
String healthTrendPath({
  TrendGroup? group,
  HealthMetricKind? metricKind,
  int windowDays = 30,
}) {
  final resolved = group ?? metricKind?.group ?? TrendGroup.recovery;
  final query = <String, String>{
    if (resolved != TrendGroup.recovery) 'group': resolved.name,
    if (metricKind != null) 'metric': metricKind.wire,
    if (windowDays != 30) 'window': '$windowDays',
  };
  return Uri(
    path: HealthRoutes.trend,
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}
