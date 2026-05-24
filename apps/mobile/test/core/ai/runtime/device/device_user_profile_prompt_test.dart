import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/device/device_user_profile_prompt.dart';

ContextPack _pack({
  RiskPreference risk = RiskPreference.moderate,
  String currency = 'CNY',
  int accountCount = 3,
  int monthsCovered = 6,
  String avgInflowMinor = '850000', // 8500.00
  String avgOutflowMinor = '420000', // 4200.00
  CashflowTrend trend = CashflowTrend.improving,
  FireGoalSummary? fireGoal,
}) {
  return ContextPack(
    version: kCurrentContextPackVersion,
    base: BaseContext(
      preferredCurrency: currency,
      riskPreference: risk,
      accounts: AccountSummary(
        totalCount: accountCount,
        byKind: const <String, int>{'cash': 1, 'security': 2},
      ),
      cashflow: CashflowSummary(
        baseCurrency: currency,
        monthsCovered: monthsCovered,
        averageInflowMinor: avgInflowMinor,
        averageOutflowMinor: avgOutflowMinor,
        trend: trend,
      ),
      fireGoal: fireGoal,
    ),
    task: const TaskContext(
      route: RouteContext(path: '/', area: 'home'),
      intent: IntentHint(
        capability: Capability.analyze,
        risk: RiskLevel.info,
      ),
    ),
    budget: PrivacyBudget.standard,
  );
}

void main() {
  group('renderContextPackSystemAppendix', () {
    test('returns null when no pack is provided', () {
      expect(renderContextPackSystemAppendix(null), isNull);
    });

    test('includes risk / currency / cashflow / FIRE bullets', () {
      final out = renderContextPackSystemAppendix(_pack(
        fireGoal: const FireGoalSummary(
          targetMinor: '25000000',
          currency: 'CNY',
          progressFraction: 0.32,
          yearsRemainingEstimate: 12.4,
        ),
      ));
      expect(out, isNotNull);
      expect(out!, startsWith('\n\n'));
      expect(out, contains('用户画像'));
      expect(out, contains('中性'));
      expect(out, contains('CNY'));
      expect(out, contains('账户数：3'));
      expect(out, contains('近 6 个月'));
      expect(out, contains('净流入改善'));
      expect(out, contains('FIRE 进度 32.0%'));
      expect(out, contains('预计 12.4 年达成'));
    });

    test('omits cashflow line when months_covered is zero', () {
      final out = renderContextPackSystemAppendix(_pack(monthsCovered: 0));
      expect(out, isNotNull);
      expect(out, isNot(contains('近')));
      expect(out, isNot(contains('月均')));
    });

    test('omits FIRE block when no goal is set', () {
      final out = renderContextPackSystemAppendix(_pack());
      expect(out, isNotNull);
      expect(out, isNot(contains('FIRE 进度')));
    });

    test('risk preference label adapts to enum value', () {
      for (final entry in <RiskPreference, String>{
        RiskPreference.conservative: '保守',
        RiskPreference.moderate: '中性',
        RiskPreference.aggressive: '激进',
      }.entries) {
        final out = renderContextPackSystemAppendix(_pack(risk: entry.key));
        expect(out, contains(entry.value), reason: entry.key.toString());
      }
    });

    test('cashflow trend label adapts to enum value', () {
      for (final entry in <CashflowTrend, String>{
        CashflowTrend.improving: '净流入改善',
        CashflowTrend.worsening: '净流入恶化',
        CashflowTrend.stable: '趋势平稳',
        CashflowTrend.unknown: '趋势未知',
      }.entries) {
        final out = renderContextPackSystemAppendix(_pack(trend: entry.key));
        expect(out, contains(entry.value), reason: entry.key.toString());
      }
    });

    test('stays well under the 1KB hard cap', () {
      final out = renderContextPackSystemAppendix(_pack(
        fireGoal: const FireGoalSummary(
          targetMinor: '25000000',
          currency: 'CNY',
          progressFraction: 0.32,
          yearsRemainingEstimate: 12.4,
        ),
      ));
      expect(out!.length, lessThan(kUserProfileAppendixByteCap));
    });

    test('compact-formats large minor amounts as 万 units', () {
      final out = renderContextPackSystemAppendix(_pack(
        avgInflowMinor: '15000000', // 150 000.00 → 15.0 万
        avgOutflowMinor: '8000000', // 80 000.00 → 8.00 万
      ));
      expect(out, contains('15.0 万'));
      // Below 100k threshold the formatter switches precision; ensure
      // the threshold still emits a 万 unit (2-decimal form).
      expect(out, contains('8.00 万'));
    });
  });
}
