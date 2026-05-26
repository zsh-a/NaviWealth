import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/amortization_entry.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/liability.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';
import 'package:naviwealth/features/liabilities/domain/liability_summary.dart';

Decimal d(String s) => Decimal.parse(s);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u1',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'dev',
  hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
);

Liability _liability() => Liability(
  id: 'lia-1',
  type: LiabilityType.mortgage,
  name: 'Mortgage',
  principal: d('120000'),
  interestRate: d('0.05'),
  currency: 'CNY',
  termMonths: 12,
  startDate: DateTime.utc(2026, 1, 1),
  sync: _meta(),
);

AmortizationEntry _row({
  required int idx,
  required String principal,
  required String interest,
  required String balance,
  bool paid = false,
}) {
  return AmortizationEntry(
    id: 'e-$idx',
    liabilityId: 'lia-1',
    periodIndex: idx,
    dueDate: DateTime.utc(2026, idx + 1, 1),
    principalPayment: d(principal),
    interestPayment: d(interest),
    remainingBalance: d(balance),
    paidAt: paid ? DateTime.utc(2026, idx + 1, 1) : null,
    sync: _meta(),
  );
}

void main() {
  test('fromSchedule sums principal/interest and counts paid periods', () {
    final schedule = [
      _row(
        idx: 1,
        principal: '10000',
        interest: '500',
        balance: '110000',
        paid: true,
      ),
      _row(
        idx: 2,
        principal: '10000',
        interest: '458',
        balance: '100000',
        paid: true,
      ),
      _row(idx: 3, principal: '10000', interest: '417', balance: '90000'),
    ];
    final s = LiabilitySummary.fromSchedule(
      liability: _liability(),
      schedule: schedule,
    );
    expect(s.totalScheduledPrincipal, d('30000'));
    expect(s.totalScheduledInterest, d('1375'));
    expect(s.principalPaid, d('20000'));
    expect(s.interestPaid, d('958'));
    expect(s.remainingPrincipal, d('10000'));
    expect(s.paidPeriods, 2);
    expect(s.totalPeriods, 3);
  });

  test('progressFraction is paid/total principal, clamped to 0-1', () {
    final s = LiabilitySummary.fromSchedule(
      liability: _liability(),
      schedule: [
        _row(idx: 1, principal: '50', interest: '0', balance: '50', paid: true),
        _row(idx: 2, principal: '50', interest: '0', balance: '0'),
      ],
    );
    expect(s.progressFraction, 0.5);
  });

  test('interestRatio is interest / total payment', () {
    final s = LiabilitySummary.fromSchedule(
      liability: _liability(),
      schedule: [_row(idx: 1, principal: '100', interest: '25', balance: '0')],
    );
    // 25 / (100 + 25) = 0.2
    expect(s.interestRatio, d('0.2'));
  });

  test('interestRatio is zero on empty/zero schedule', () {
    final s = LiabilitySummary.fromSchedule(
      liability: _liability(),
      schedule: const [],
    );
    expect(s.interestRatio, Decimal.zero);
    expect(s.progressFraction, 0.0);
  });
}
