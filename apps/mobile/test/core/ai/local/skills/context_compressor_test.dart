import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';

void main() {
  const compressor = ContextCompressor();

  group('compressBase', () {
    test('uses provided base currency', () {
      final base = compressor.compressBase(baseCurrency: 'CNY');
      expect(base.preferredCurrency, 'CNY');
      expect(base.cashflow.baseCurrency, 'CNY');
    });

    test('falls back to USD when currency null', () {
      final base = compressor.compressBase();
      expect(base.preferredCurrency, 'USD');
    });

    test('Phase 1 defaults are honest about missing data', () {
      final base = compressor.compressBase(baseCurrency: 'USD');
      expect(base.riskPreference, RiskPreference.moderate);
      expect(base.accounts.totalCount, 0);
      expect(base.accounts.byKind, isEmpty);
      expect(base.cashflow.monthsCovered, 0);
      expect(base.cashflow.trend, CashflowTrend.unknown);
      expect(base.fireGoal, isNull);
    });
  });

  group('compressTask signals', () {
    const route = RouteContext(path: '/expense', area: 'expense');
    const intent = IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.suggest,
    );

    test('no inputs → no signals', () {
      final task = compressor.compressTask(route: route, intent: intent);
      expect(task.signals, isEmpty);
    });

    test('expense anomaly produces a spending_spike signal', () {
      final task = compressor.compressTask(
        route: route,
        intent: intent,
        expenseAnomalyDelta: 0.37,
      );
      expect(task.signals, hasLength(1));
      final s = task.signals.single;
      expect(s.kind, SignalKind.spendingSpike);
      expect(s.severity, SignalSeverity.warn);
      expect(s.summaryZh, contains('37%'));
    });

    test('large anomaly delta escalates to critical', () {
      final task = compressor.compressTask(
        route: route,
        intent: intent,
        expenseAnomalyDelta: 0.8,
      );
      expect(task.signals.single.severity, SignalSeverity.critical);
    });

    test('deposit maturity produces a deposit_maturing signal', () {
      final task = compressor.compressTask(
        route: route,
        intent: intent,
        depositMaturityCount: 2,
        depositMaturityDays: 7,
      );
      expect(task.signals, hasLength(1));
      final s = task.signals.single;
      expect(s.kind, SignalKind.depositMaturing);
      expect(s.severity, SignalSeverity.info);
      expect(s.summaryZh, contains('2'));
      expect(s.summaryZh, contains('7'));
    });

    test('zero maturity count is suppressed', () {
      final task = compressor.compressTask(
        route: route,
        intent: intent,
        depositMaturityCount: 0,
        depositMaturityDays: 14,
      );
      expect(task.signals, isEmpty);
    });

    test('signals list is unmodifiable', () {
      final task = compressor.compressTask(
        route: route,
        intent: intent,
        expenseAnomalyDelta: 0.1,
      );
      expect(
        () => task.signals.add(
          const RecentSignal(
            kind: SignalKind.other,
            severity: SignalSeverity.info,
            summaryZh: '',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('compress (full pack)', () {
    test('produces budget-conformant pack with both signals', () {
      final pack = compressor.compress(
        route: const RouteContext(path: '/home', area: 'home'),
        intent: const IntentHint(
          capability: Capability.summarize,
          risk: RiskLevel.info,
          label: 'monthly_pulse',
        ),
        baseCurrency: 'USD',
        expenseAnomalyDelta: 0.3,
        depositMaturityCount: 1,
        depositMaturityDays: 5,
      );
      expect(pack.version, kCurrentContextPackVersion);
      expect(pack.budget.tier, BudgetTier.standard);
      expect(pack.task.signals, hasLength(2));
      expect(pack.serializedByteSize, lessThan(BudgetTier.standard.byteCap));
      // Sanity: still well below the small tier as well, given Phase 1
      // base context is sparse.
      expect(pack.serializedByteSize, lessThan(BudgetTier.small.byteCap));
    });

    test('honours an explicit small budget', () {
      final pack = compressor.compress(
        route: const RouteContext(path: '/home', area: 'home'),
        intent: const IntentHint(
          capability: Capability.classify,
          risk: RiskLevel.info,
        ),
        budget: PrivacyBudget.small,
      );
      expect(pack.budget.tier, BudgetTier.small);
    });
  });
}
