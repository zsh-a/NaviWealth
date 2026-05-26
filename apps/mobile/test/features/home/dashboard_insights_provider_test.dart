import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/assets/data/deposit_maturity_insight_provider.dart';
import 'package:naviwealth/features/expense/data/expense_anomaly_insight_provider.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/domain/manual_asset_metadata.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/rebalance/data/rebalance_drift_insight_provider.dart';
import 'package:naviwealth/features/rebalance/domain/rebalance_models.dart';

class _IdentityConverter implements CurrencyConverter {
  const _IdentityConverter();

  @override
  Money convert(Money amount, String to, {DateTime? on}) {
    if (amount.currency == to) return amount;
    throw FxRateNotFoundError(amount.currency, to, on);
  }
}

final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'd',
  hlc: Hlc.zero('d'),
);

void main() {
  test('summarizeRebalanceDrift returns the largest threshold breach', () {
    final plan = RebalancePlan(
      target: const TargetAllocation(weights: {}),
      actualWeights: const {},
      drifts: const [
        Drift(
          category: AssetCategory.cash,
          actualWeight: 0.20,
          targetWeight: 0.18,
          severity: DriftSeverity.ok,
        ),
        Drift(
          category: AssetCategory.stock,
          actualWeight: 0.40,
          targetWeight: 0.30,
          severity: DriftSeverity.warning,
        ),
      ],
      trades: const [],
      estimatedFees: Money.fromInt(0, 'CNY'),
      estimatedTaxes: Money.fromInt(0, 'CNY'),
      driftBeforePct: 0.10,
      driftAfterPct: 0,
      totalAssets: Money.fromInt(1000, 'CNY'),
    );

    final summary = summarizeRebalanceDrift(plan, threshold: 0.05);

    expect(summary?.category, AssetCategory.stock);
    expect(summary?.deviation, closeTo(0.10, 0.0001));
  });

  test('summarizeDepositMaturities counts deposits inside the window', () {
    final now = DateTime.utc(2026, 5, 8);
    final summary = summarizeDepositMaturities(
      now: now,
      assets: [
        _deposit('due-1', now.add(const Duration(days: 3))),
        _deposit('due-2', now.add(const Duration(days: 10))),
        _deposit('late', now.add(const Duration(days: 30))),
      ],
    );

    expect(summary?.count, 2);
    expect(summary?.days, 3);
  });

  test('summarizeExpenseAnomaly emits only threshold-level projections', () {
    final now = DateTime.utc(2026, 5, 15);
    final summary = summarizeExpenseAnomaly(
      now: now,
      converter: const _IdentityConverter(),
      baseCurrency: 'CNY',
      expenses: [
        _expense('current', '1000', DateTime.utc(2026, 5, 10)),
        _expense('m-1', '300', DateTime.utc(2026, 4, 10)),
        _expense('m-2', '300', DateTime.utc(2026, 3, 10)),
        _expense('m-3', '300', DateTime.utc(2026, 2, 10)),
      ],
    );

    expect(summary, isNotNull);
    expect(summary!.deltaRatio, greaterThan(1));
  });
}

Asset _deposit(String id, DateTime maturityDate) {
  return Asset(
    id: id,
    type: AssetType.bankDepositTerm,
    symbol: id,
    currency: 'CNY',
    metadataJson: DepositMetadata(
      accountId: 'acct',
      principal: Decimal.parse('100'),
      interestRate: Decimal.parse('0.02'),
      maturityDate: maturityDate,
    ).encode(),
    sync: _sync,
  );
}

Expense _expense(String id, String amount, DateTime date) {
  return Expense(
    id: id,
    expenseAccountId: 'expense',
    amount: Decimal.parse(amount),
    currency: 'CNY',
    tradeDate: date,
    sync: _sync,
  );
}
