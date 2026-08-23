import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/memory/memory_access_policy.dart';

void main() {
  test('deny-all policy fails closed', () {
    const policy = MemoryAccessPolicy.denyAll();
    expect(policy.isEmpty, isTrue);
    expect(policy.allowsSource('fin:anything'), isFalse);
  });

  test('allow-list matches literal source prefixes', () {
    final policy = MemoryAccessPolicy.allowPrefixes(const <String>[
      'fin:',
      'health:metrics',
      ' ',
    ]);
    expect(policy.allowsSource('fin:decisions'), isTrue);
    expect(policy.allowsSource('health:metrics:sleep'), isTrue);
    expect(policy.allowsSource('health:other'), isFalse);
    expect(policy.allowsSource(null), isFalse);
  });
}
