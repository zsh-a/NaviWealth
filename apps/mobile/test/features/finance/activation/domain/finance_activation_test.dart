import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/activation/domain/finance_activation.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';

void main() {
  test('activation follows ledger, review, and runway evidence', () {
    expect(
      buildFinanceActivation(
        hasLedgerData: false,
        pendingReviewCount: 0,
        runway: null,
      ).stage,
      FinanceActivationStage.addData,
    );
    expect(
      buildFinanceActivation(
        hasLedgerData: false,
        pendingReviewCount: 2,
        runway: null,
      ).stage,
      FinanceActivationStage.reviewData,
    );
    expect(
      buildFinanceActivation(
        hasLedgerData: true,
        pendingReviewCount: 0,
        runway: null,
      ).stage,
      FinanceActivationStage.reviewRunway,
    );

    final completed = buildFinanceActivation(
      hasLedgerData: true,
      pendingReviewCount: 0,
      runway: _runway(),
    );
    expect(completed.stage, FinanceActivationStage.complete);
    expect(completed.completedSteps, FinanceActivationSnapshot.totalSteps);
  });

  test('manual ledger data satisfies the first activation step', () {
    final snapshot = buildFinanceActivation(
      hasLedgerData: true,
      pendingReviewCount: 0,
      runway: null,
    );

    expect(snapshot.stage, FinanceActivationStage.reviewRunway);
    expect(snapshot.completedSteps, 2);
  });
}

MoneyRunwaySnapshot _runway() => buildMoneyRunway(
  asOf: DateTime.utc(2026, 7, 1),
  currency: 'CNY',
  startingBalance: Decimal.fromInt(10000),
  reserveTarget: Decimal.fromInt(3000),
  averageMonthlyExpense: Decimal.fromInt(3000),
  estimatedDailyVariableOutflow: Decimal.fromInt(100),
  scheduledFlows: const [],
  confidence: MoneyRunwayConfidence.low,
  dataCompleteness: 0.25,
  missingCurrencies: const {},
  hasData: true,
);
