part of 'dividend_forecast.dart';

const _portfolioAssetId = 'portfolio';

ProjectedDividend _result({
  required String assetId,
  required Map<DateTime, Decimal> schedule,
  required String currency,
  required String strategy,
  required DividendForecastConfidence confidence,
}) {
  return ProjectedDividend(
    assetId: assetId,
    perAsset: Map.unmodifiable(schedule),
    total: _sum(schedule.values),
    currency: currency,
    strategy: strategy,
    confidence: confidence,
    strategyBreakdown: schedule.isEmpty
        ? const <String, Decimal>{}
        : Map.unmodifiable({strategy: _sum(schedule.values)}),
  );
}

bool _hasOpenQuantity(HoldingSnapshot holding) =>
    holding.quantity > Decimal.zero;

String _assetIdFor(List<HoldingSnapshot> holdings) =>
    holdings.length == 1 ? holdings.single.assetId : _portfolioAssetId;

String _forecastCurrency(
  Iterable<HoldingSnapshot> holdings,
  Iterable<CashDividend> history,
  Iterable<CorporateAction> declared,
) {
  final holding = holdings.firstOrNull;
  if (holding != null) return holding.baseCurrency;
  final dividend = history.firstOrNull;
  if (dividend != null) return dividend.currency;
  for (final action in declared) {
    switch (action) {
      case CashDividendAction a:
        return a.currency;
      case DripAction a:
        return a.currency;
      default:
        continue;
    }
  }
  return '';
}

int _estimatedAnnualFrequency(List<CashDividend> history) {
  if (history.length <= 1) return 1;
  var totalGapDays = 0;
  var gaps = 0;
  for (var i = 1; i < history.length; i++) {
    final gap = history[i].effectiveDate
        .toUtc()
        .difference(history[i - 1].effectiveDate.toUtc())
        .inDays
        .abs();
    if (gap == 0) continue;
    totalGapDays += gap;
    gaps++;
  }
  if (gaps == 0) return 1;
  final averageGap = totalGapDays / gaps;
  if (averageGap <= 45) return 12;
  if (averageGap <= 100) return 4;
  if (averageGap <= 200) return 2;
  return 1;
}

DividendForecastConfidence _lowestConfidence(
  DividendForecastConfidence a,
  DividendForecastConfidence b,
) {
  return a.index >= b.index ? a : b;
}

void _addToSchedule(
  Map<DateTime, Decimal> schedule,
  DateTime date,
  Decimal amount,
) {
  if (amount <= Decimal.zero) return;
  final key = _utcDay(date);
  schedule[key] = (schedule[key] ?? Decimal.zero) + amount;
}

Decimal _sum(Iterable<Decimal> values) {
  var total = Decimal.zero;
  for (final value in values) {
    total += value;
  }
  return total;
}

DateTime _utcDay(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

DateTime _addMonths(DateTime date, int delta) {
  final utc = date.toUtc();
  final monthIndex = utc.year * 12 + utc.month - 1 + delta;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = utc.day > lastDay ? lastDay : utc.day;
  return DateTime.utc(
    year,
    month,
    day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  );
}
