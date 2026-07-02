import 'package:decimal/decimal.dart';

import 'options_strategy_profile.dart';
import 'trade_journal_entry.dart';

class OptionsTradeStats {
  const OptionsTradeStats({
    required this.totalEntries,
    required this.openEntries,
    required this.closedEntries,
    required this.assignedEntries,
    required this.expiredEntries,
    required this.byCurrency,
    required this.byStrategy,
    required this.bySymbol,
  });

  final int totalEntries;
  final int openEntries;
  final int closedEntries;
  final int assignedEntries;
  final int expiredEntries;
  final List<OptionsCurrencyStats> byCurrency;
  final List<OptionsStrategyStats> byStrategy;
  final List<OptionsSymbolStats> bySymbol;

  bool get isEmpty => totalEntries == 0;

  OptionsCurrencyStats? get primaryCurrency =>
      byCurrency.isEmpty ? null : byCurrency.first;
}

class OptionsCurrencyStats {
  const OptionsCurrencyStats({
    required this.currency,
    required this.entryCount,
    required this.totalPremium,
    required this.trackedRealizedPnl,
    required this.trackedRealizedCount,
    required this.winningCount,
    required this.losingCount,
    required this.averageRealizedPnl,
    required this.averageHoldingDays,
  });

  final String currency;
  final int entryCount;
  final Decimal totalPremium;
  final Decimal trackedRealizedPnl;
  final int trackedRealizedCount;
  final int winningCount;
  final int losingCount;
  final Decimal averageRealizedPnl;
  final double? averageHoldingDays;

  double? get winRate {
    if (trackedRealizedCount == 0) return null;
    return winningCount / trackedRealizedCount;
  }
}

class OptionsStrategyStats {
  const OptionsStrategyStats({
    required this.strategy,
    required this.entryCount,
    required this.openCount,
    required this.totalPremiumByCurrency,
    required this.trackedRealizedPnlByCurrency,
  });

  final OptionsStrategyKind strategy;
  final int entryCount;
  final int openCount;
  final Map<String, Decimal> totalPremiumByCurrency;
  final Map<String, Decimal> trackedRealizedPnlByCurrency;
}

class OptionsSymbolStats {
  const OptionsSymbolStats({
    required this.symbol,
    required this.entryCount,
    required this.openCount,
    required this.assignedCount,
    required this.expiredCount,
    required this.totalPremiumByCurrency,
    required this.trackedRealizedPnlByCurrency,
  });

  final String symbol;
  final int entryCount;
  final int openCount;
  final int assignedCount;
  final int expiredCount;
  final Map<String, Decimal> totalPremiumByCurrency;
  final Map<String, Decimal> trackedRealizedPnlByCurrency;
}

OptionsTradeStats buildOptionsTradeStats(Iterable<TradeJournalEntry> entries) {
  final rows = entries.toList(growable: false);
  final currencyAcc = <String, _CurrencyAccumulator>{};
  final strategyAcc = <OptionsStrategyKind, _StrategyAccumulator>{};
  final symbolAcc = <String, _SymbolAccumulator>{};
  var open = 0;
  var closed = 0;
  var assigned = 0;
  var expired = 0;

  for (final entry in rows) {
    switch (entry.status) {
      case TradeJournalStatus.open:
        open++;
      case TradeJournalStatus.closed:
        closed++;
      case TradeJournalStatus.assigned:
        assigned++;
      case TradeJournalStatus.expired:
        expired++;
    }

    final currency = entry.currency.trim().toUpperCase();
    final realized = trackedRealizedPnl(entry);
    final holdingDays = _holdingDays(entry);

    currencyAcc
        .putIfAbsent(currency, () => _CurrencyAccumulator(currency))
        .add(entry, realized: realized, holdingDays: holdingDays);
    strategyAcc
        .putIfAbsent(entry.strategy, () => _StrategyAccumulator(entry.strategy))
        .add(entry, currency: currency, realized: realized);
    symbolAcc
        .putIfAbsent(entry.symbol, () => _SymbolAccumulator(entry.symbol))
        .add(entry, currency: currency, realized: realized);
  }

  final byCurrency = currencyAcc.values.map((a) => a.build()).toList()
    ..sort((a, b) {
      final byEntries = b.entryCount.compareTo(a.entryCount);
      if (byEntries != 0) return byEntries;
      return a.currency.compareTo(b.currency);
    });
  final byStrategy = strategyAcc.values.map((a) => a.build()).toList()
    ..sort((a, b) => a.strategy.index.compareTo(b.strategy.index));
  final bySymbol = symbolAcc.values.map((a) => a.build()).toList()
    ..sort((a, b) {
      final pnlA = a.trackedRealizedPnlByCurrency.values.fold(
        Decimal.zero,
        (sum, value) => sum + value,
      );
      final pnlB = b.trackedRealizedPnlByCurrency.values.fold(
        Decimal.zero,
        (sum, value) => sum + value,
      );
      final byPnl = pnlB.compareTo(pnlA);
      if (byPnl != 0) return byPnl;
      return b.entryCount.compareTo(a.entryCount);
    });

  return OptionsTradeStats(
    totalEntries: rows.length,
    openEntries: open,
    closedEntries: closed,
    assignedEntries: assigned,
    expiredEntries: expired,
    byCurrency: byCurrency,
    byStrategy: byStrategy,
    bySymbol: bySymbol,
  );
}

Decimal? trackedRealizedPnl(TradeJournalEntry entry) {
  final explicit = entry.realizedPnl;
  if (explicit != null) return explicit;
  final exitDebit = entry.exitDebit;
  if (exitDebit != null) return entry.entryCredit - exitDebit;
  if (entry.status == TradeJournalStatus.expired) return entry.entryCredit;
  return null;
}

double? _holdingDays(TradeJournalEntry entry) {
  final end = entry.closedAt;
  if (end == null) return null;
  final duration = end.toUtc().difference(entry.openedAt.toUtc());
  if (duration.isNegative) return null;
  return duration.inHours / 24;
}

class _CurrencyAccumulator {
  _CurrencyAccumulator(this.currency);

  final String currency;
  var entryCount = 0;
  var totalPremium = Decimal.zero;
  var trackedRealizedPnl = Decimal.zero;
  var trackedRealizedCount = 0;
  var winningCount = 0;
  var losingCount = 0;
  var holdingDaysTotal = 0.0;
  var holdingDaysCount = 0;

  void add(
    TradeJournalEntry entry, {
    required Decimal? realized,
    required double? holdingDays,
  }) {
    entryCount++;
    totalPremium += entry.entryCredit;
    if (realized != null) {
      trackedRealizedPnl += realized;
      trackedRealizedCount++;
      if (realized > Decimal.zero) {
        winningCount++;
      } else if (realized < Decimal.zero) {
        losingCount++;
      }
    }
    if (holdingDays != null) {
      holdingDaysTotal += holdingDays;
      holdingDaysCount++;
    }
  }

  OptionsCurrencyStats build() {
    return OptionsCurrencyStats(
      currency: currency,
      entryCount: entryCount,
      totalPremium: totalPremium,
      trackedRealizedPnl: trackedRealizedPnl,
      trackedRealizedCount: trackedRealizedCount,
      winningCount: winningCount,
      losingCount: losingCount,
      averageRealizedPnl: trackedRealizedCount == 0
          ? Decimal.zero
          : (trackedRealizedPnl / Decimal.fromInt(trackedRealizedCount))
                .toDecimal(scaleOnInfinitePrecision: 2),
      averageHoldingDays: holdingDaysCount == 0
          ? null
          : holdingDaysTotal / holdingDaysCount,
    );
  }
}

class _StrategyAccumulator {
  _StrategyAccumulator(this.strategy);

  final OptionsStrategyKind strategy;
  var entryCount = 0;
  var openCount = 0;
  final totalPremiumByCurrency = <String, Decimal>{};
  final trackedRealizedPnlByCurrency = <String, Decimal>{};

  void add(
    TradeJournalEntry entry, {
    required String currency,
    required Decimal? realized,
  }) {
    entryCount++;
    if (entry.status == TradeJournalStatus.open) openCount++;
    _addMoney(totalPremiumByCurrency, currency, entry.entryCredit);
    if (realized != null) {
      _addMoney(trackedRealizedPnlByCurrency, currency, realized);
    }
  }

  OptionsStrategyStats build() {
    return OptionsStrategyStats(
      strategy: strategy,
      entryCount: entryCount,
      openCount: openCount,
      totalPremiumByCurrency: Map.unmodifiable(totalPremiumByCurrency),
      trackedRealizedPnlByCurrency: Map.unmodifiable(
        trackedRealizedPnlByCurrency,
      ),
    );
  }
}

class _SymbolAccumulator {
  _SymbolAccumulator(this.symbol);

  final String symbol;
  var entryCount = 0;
  var openCount = 0;
  var assignedCount = 0;
  var expiredCount = 0;
  final totalPremiumByCurrency = <String, Decimal>{};
  final trackedRealizedPnlByCurrency = <String, Decimal>{};

  void add(
    TradeJournalEntry entry, {
    required String currency,
    required Decimal? realized,
  }) {
    entryCount++;
    switch (entry.status) {
      case TradeJournalStatus.open:
        openCount++;
      case TradeJournalStatus.closed:
        break;
      case TradeJournalStatus.assigned:
        assignedCount++;
      case TradeJournalStatus.expired:
        expiredCount++;
    }
    _addMoney(totalPremiumByCurrency, currency, entry.entryCredit);
    if (realized != null) {
      _addMoney(trackedRealizedPnlByCurrency, currency, realized);
    }
  }

  OptionsSymbolStats build() {
    return OptionsSymbolStats(
      symbol: symbol,
      entryCount: entryCount,
      openCount: openCount,
      assignedCount: assignedCount,
      expiredCount: expiredCount,
      totalPremiumByCurrency: Map.unmodifiable(totalPremiumByCurrency),
      trackedRealizedPnlByCurrency: Map.unmodifiable(
        trackedRealizedPnlByCurrency,
      ),
    );
  }
}

void _addMoney(Map<String, Decimal> target, String currency, Decimal amount) {
  target.update(currency, (value) => value + amount, ifAbsent: () => amount);
}
