part of 'cashflow_page.dart';

class _CashFlowViewModel {
  const _CashFlowViewModel({
    required this.baseCurrency,
    required this.periods,
    required this.currentInflow,
    required this.currentOutflow,
    required this.currentNet,
    required this.categories,
    required this.categoryTotal,
  });

  final String baseCurrency;
  final List<_PeriodTotal> periods;
  final _MoneyBreakdown currentInflow;
  final _MoneyBreakdown currentOutflow;
  final _MoneyBreakdown currentNet;
  final List<_CategoryTotal> categories;
  final Decimal categoryTotal;

  factory _CashFlowViewModel.fromSummary(
    CashFlowSummary summary, {
    required List<String> visibleKeys,
    required String currentKey,
  }) {
    final byPeriod = {
      for (final key in visibleKeys)
        key: _PeriodAcc(
          key: key,
          label: _shortPeriodLabel(key, summary.period),
          date: _periodDate(key, summary.period),
        ),
    };
    final current = _CurrentAcc(summary.baseCurrency);
    final categoryAcc = <CashFlowKind, Decimal>{};

    for (final bucket in summary.buckets) {
      final amount = bucket.totalInBase.amount;
      final periodAcc = byPeriod[bucket.key];
      if (periodAcc != null) {
        if (_isIncomeKind(bucket.kind) && amount > Decimal.zero) {
          periodAcc.inflow += amount;
        } else if (bucket.kind == CashFlowKind.expense) {
          periodAcc.outflow += amount.abs();
        }
      }
      if (bucket.key == currentKey) {
        current.add(bucket);
        final magnitude = amount.abs();
        if (magnitude > Decimal.zero) {
          categoryAcc.update(
            bucket.kind,
            (value) => value + magnitude,
            ifAbsent: () => magnitude,
          );
        }
      }
    }

    final categories =
        categoryAcc.entries
            .map(
              (entry) => _CategoryTotal(
                kind: entry.key,
                amount: entry.value,
                currency: summary.baseCurrency,
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
    final categoryTotal = categories.fold<Decimal>(
      Decimal.zero,
      (sum, category) => sum + category.amount,
    );

    return _CashFlowViewModel(
      baseCurrency: summary.baseCurrency,
      periods: List.unmodifiable(byPeriod.values),
      currentInflow: current.inflow,
      currentOutflow: current.outflow,
      currentNet: current.net,
      categories: List.unmodifiable(categories),
      categoryTotal: categoryTotal,
    );
  }
}

class _PeriodAcc {
  _PeriodAcc({required this.key, required this.label, required this.date});

  final String key;
  final String label;
  final DateTime date;
  Decimal inflow = Decimal.zero;
  Decimal outflow = Decimal.zero;

  Decimal get net => inflow - outflow;
}

typedef _PeriodTotal = _PeriodAcc;

class _CurrentAcc {
  _CurrentAcc(this.baseCurrency);

  final String baseCurrency;
  Decimal inflowBase = Decimal.zero;
  Decimal outflowBase = Decimal.zero;
  Decimal netBase = Decimal.zero;
  final inflowOriginals = <String, Decimal>{};
  final outflowOriginals = <String, Decimal>{};
  final netOriginals = <String, Decimal>{};

  void add(CashFlowBucket bucket) {
    final amount = bucket.totalInBase.amount;
    final original = bucket.originalTotal.amount;
    netBase += amount;
    _add(netOriginals, bucket.currency, original);
    if (amount > Decimal.zero) {
      inflowBase += amount;
      _add(inflowOriginals, bucket.currency, original.abs());
    } else if (amount < Decimal.zero) {
      outflowBase += amount.abs();
      _add(outflowOriginals, bucket.currency, original.abs());
    }
  }

  _MoneyBreakdown get inflow => _MoneyBreakdown(
    baseAmount: inflowBase,
    baseCurrency: baseCurrency,
    originals: Map.unmodifiable(inflowOriginals),
  );

  _MoneyBreakdown get outflow => _MoneyBreakdown(
    baseAmount: outflowBase,
    baseCurrency: baseCurrency,
    originals: Map.unmodifiable(outflowOriginals),
  );

  _MoneyBreakdown get net => _MoneyBreakdown(
    baseAmount: netBase,
    baseCurrency: baseCurrency,
    originals: Map.unmodifiable(netOriginals),
  );
}

class _CategoryTotal {
  const _CategoryTotal({
    required this.kind,
    required this.amount,
    required this.currency,
  });

  final CashFlowKind kind;
  final Decimal amount;
  final String currency;
}

void _add(Map<String, Decimal> map, String currency, Decimal amount) {
  map.update(currency, (value) => value + amount, ifAbsent: () => amount);
}

bool _isIncomeKind(CashFlowKind kind) {
  return switch (kind) {
    CashFlowKind.salary ||
    CashFlowKind.dividend ||
    CashFlowKind.interest ||
    CashFlowKind.capitalGains ||
    CashFlowKind.otherIncome => true,
    CashFlowKind.expense ||
    CashFlowKind.transfer ||
    CashFlowKind.opening ||
    CashFlowKind.other => false,
  };
}

CashFlowPeriod _periodFromUri(Uri uri) {
  final value = uri.queryParameters['period'];
  return switch (value) {
    'quarter' => CashFlowPeriod.quarter,
    'year' => CashFlowPeriod.year,
    _ => CashFlowPeriod.month,
  };
}

String _periodLabel(AppLocalizations l10n, CashFlowPeriod period) {
  return switch (period) {
    CashFlowPeriod.month => l10n.cashFlowPeriodMonth,
    CashFlowPeriod.quarter => l10n.cashFlowPeriodQuarter,
    CashFlowPeriod.year => l10n.cashFlowPeriodYear,
  };
}

String _kindLabel(AppLocalizations l10n, CashFlowKind kind) {
  return switch (kind) {
    CashFlowKind.salary => l10n.cashFlowKindSalary,
    CashFlowKind.dividend => l10n.cashFlowKindDividend,
    CashFlowKind.interest => l10n.cashFlowKindInterest,
    CashFlowKind.capitalGains => l10n.cashFlowKindCapitalGains,
    CashFlowKind.otherIncome => l10n.cashFlowKindOtherIncome,
    CashFlowKind.expense => l10n.cashFlowKindExpense,
    CashFlowKind.transfer => l10n.cashFlowKindTransfer,
    CashFlowKind.opening => l10n.cashFlowKindOpening,
    CashFlowKind.other => l10n.cashFlowKindOther,
  };
}

List<String> _visibleKeys(CashFlowPeriod period, DateTime now) {
  final count = switch (period) {
    CashFlowPeriod.month => 12,
    CashFlowPeriod.quarter => 8,
    CashFlowPeriod.year => 5,
  };
  return [
    for (var i = count - 1; i >= 0; i--)
      _periodKey(_minusPeriods(now, period, i), period),
  ];
}

DateTime _minusPeriods(DateTime date, CashFlowPeriod period, int count) {
  return switch (period) {
    CashFlowPeriod.month => DateTime.utc(date.year, date.month - count, 1),
    CashFlowPeriod.quarter => DateTime.utc(
      date.year,
      date.month - count * 3,
      1,
    ),
    CashFlowPeriod.year => DateTime.utc(date.year - count, 1, 1),
  };
}

String _periodKey(DateTime date, CashFlowPeriod period) {
  return switch (period) {
    CashFlowPeriod.month =>
      '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}',
    CashFlowPeriod.quarter =>
      '${date.year.toString().padLeft(4, '0')}-Q'
          '${((date.month - 1) ~/ 3) + 1}',
    CashFlowPeriod.year => date.year.toString().padLeft(4, '0'),
  };
}

DateTime _periodDate(String key, CashFlowPeriod period) {
  return switch (period) {
    CashFlowPeriod.month => DateTime.utc(
      int.parse(key.substring(0, 4)),
      int.parse(key.substring(5, 7)),
      1,
    ),
    CashFlowPeriod.quarter => DateTime.utc(
      int.parse(key.substring(0, 4)),
      (int.parse(key.substring(6, 7)) - 1) * 3 + 1,
      1,
    ),
    CashFlowPeriod.year => DateTime.utc(int.parse(key), 1, 1),
  };
}

String _shortPeriodLabel(String key, CashFlowPeriod period) {
  return switch (period) {
    CashFlowPeriod.month => key.substring(5, 7),
    CashFlowPeriod.quarter => key.substring(5),
    CashFlowPeriod.year => key,
  };
}
