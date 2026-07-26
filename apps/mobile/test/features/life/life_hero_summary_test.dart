import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/features/life/data/life_events_provider.dart';

void main() {
  test('primaryMetric prefers high-priority count', () {
    const summary = LifeHeroSummary(
      domainCount: 3,
      signalCount: 7,
      highPriorityCount: 2,
      signalCountByDomain: {
        DomainScope.finance: 3,
        DomainScope.health: 2,
        DomainScope.execution: 2,
      },
      highCountByDomain: {DomainScope.health: 1, DomainScope.execution: 1},
    );

    expect(summary.primaryMetric, 2);
    expect(summary.hasAttention, isTrue);
    expect(summary.isCalm, isFalse);
    expect(summary.signalsFor(DomainScope.finance), 3);
    expect(summary.highFor(DomainScope.health), 1);
    expect(summary.highFor(DomainScope.knowledge), 0);
  });

  test(
    'primaryMetric falls back to total signals when calm of high-priority',
    () {
      const summary = LifeHeroSummary(
        domainCount: 2,
        signalCount: 4,
        highPriorityCount: 0,
      );

      expect(summary.primaryMetric, 4);
      expect(summary.hasAttention, isFalse);
      expect(summary.isCalm, isFalse);
    },
  );

  test('calm when no signals', () {
    const summary = LifeHeroSummary(
      domainCount: 2,
      signalCount: 0,
      highPriorityCount: 0,
    );

    expect(summary.primaryMetric, 0);
    expect(summary.isCalm, isTrue);
  });
}
