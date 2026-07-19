import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/activation/domain/finance_activation.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';

void main() {
  test('activation follows real import, review, and runway evidence', () {
    expect(
      buildFinanceActivation(
        confirmedImportCount: 0,
        pendingReviewCount: 0,
        runway: null,
      ).stage,
      FinanceActivationStage.importData,
    );
    expect(
      buildFinanceActivation(
        confirmedImportCount: 0,
        pendingReviewCount: 2,
        runway: null,
      ).stage,
      FinanceActivationStage.reviewImport,
    );
    expect(
      buildFinanceActivation(
        confirmedImportCount: 2,
        pendingReviewCount: 0,
        runway: null,
      ).stage,
      FinanceActivationStage.reviewRunway,
    );

    final completed = buildFinanceActivation(
      confirmedImportCount: 2,
      pendingReviewCount: 0,
      runway: _runway(),
    );
    expect(completed.stage, FinanceActivationStage.complete);
    expect(completed.completedSteps, FinanceActivationSnapshot.totalSteps);
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
