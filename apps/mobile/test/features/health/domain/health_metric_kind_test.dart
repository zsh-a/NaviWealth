import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';

void main() {
  test('trend direction reflects health metric semantics', () {
    expect(HealthMetricKind.hrvDaily.higherIsBetter, isTrue);
    expect(HealthMetricKind.sleepSession.higherIsBetter, isTrue);
    expect(HealthMetricKind.rhrDaily.higherIsBetter, isFalse);
    expect(HealthMetricKind.stressDaily.higherIsBetter, isFalse);
    expect(HealthMetricKind.weight.higherIsBetter, isNull);
  });
}
