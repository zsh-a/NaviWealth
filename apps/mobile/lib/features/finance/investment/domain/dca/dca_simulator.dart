import 'package:decimal/decimal.dart';

const int _scale = 16;

enum DcaFrequency { monthly, quarterly }

class DcaSimulationInput {
  const DcaSimulationInput({
    required this.allocations,
    required this.amountPerContribution,
    required this.currency,
    required this.from,
    required this.to,
    required this.frequency,
    required this.priceSeries,
  });

  final List<DcaAllocation> allocations;
  final Decimal amountPerContribution;
  final String currency;
  final DateTime from;
  final DateTime to;
  final DcaFrequency frequency;
  final Map<String, List<DcaPricePoint>> priceSeries;
}

class DcaAllocation {
  const DcaAllocation({required this.symbol, required this.weight});

  final String symbol;
  final Decimal weight;
}

class DcaPricePoint {
  const DcaPricePoint({required this.asOf, required this.close});

  final DateTime asOf;
  final Decimal close;
}

class DcaSimulationResult {
  const DcaSimulationResult({
    required this.currency,
    required this.contributions,
    required this.positions,
    required this.equityCurve,
    required this.totalInvested,
    required this.endingValue,
    required this.cumulativeReturn,
    required this.averageCost,
    required this.maxDrawdown,
  });

  final String currency;
  final List<DcaContribution> contributions;
  final List<DcaPositionResult> positions;
  final List<DcaEquityPoint> equityCurve;
  final Decimal totalInvested;
  final Decimal endingValue;
  final Decimal cumulativeReturn;
  final Decimal averageCost;
  final Decimal maxDrawdown;

  bool get isEmpty => contributions.isEmpty;
}

class DcaContribution {
  const DcaContribution({
    required this.asOf,
    required this.symbol,
    required this.amount,
    required this.price,
    required this.quantity,
  });

  final DateTime asOf;
  final String symbol;
  final Decimal amount;
  final Decimal price;
  final Decimal quantity;
}

class DcaPositionResult {
  const DcaPositionResult({
    required this.symbol,
    required this.quantity,
    required this.invested,
    required this.endingValue,
    required this.averageCost,
  });

  final String symbol;
  final Decimal quantity;
  final Decimal invested;
  final Decimal endingValue;
  final Decimal averageCost;
}

class DcaEquityPoint {
  const DcaEquityPoint({required this.asOf, required this.value});

  final DateTime asOf;
  final Decimal value;
}

class DcaSimulator {
  const DcaSimulator();

  DcaSimulationResult simulate(DcaSimulationInput input) {
    final normalized = _normalizeAllocations(input.allocations);
    if (normalized.isEmpty ||
        input.amountPerContribution <= Decimal.zero ||
        !input.from.isBefore(input.to)) {
      return _empty(input.currency);
    }

    final series = <String, List<DcaPricePoint>>{};
    for (final allocation in normalized) {
      final points =
          (input.priceSeries[allocation.symbol] ?? const [])
              .where(
                (p) =>
                    !p.asOf.isBefore(input.from) &&
                    !p.asOf.isAfter(input.to) &&
                    p.close > Decimal.zero,
              )
              .toList()
            ..sort((a, b) => a.asOf.compareTo(b.asOf));
      if (points.isNotEmpty) series[allocation.symbol] = points;
    }
    if (series.isEmpty) return _empty(input.currency);

    final dates = _unionDates(series.values);
    final schedule = _schedule(input.from, input.to, input.frequency);
    final contributions = <DcaContribution>[];
    final quantities = <String, Decimal>{};
    final invested = <String, Decimal>{};
    final nextScheduleBySymbol = {
      for (final allocation in normalized) allocation.symbol: 0,
    };
    final equityCurve = <DcaEquityPoint>[];
    var totalInvested = Decimal.zero;
    var peak = Decimal.zero;
    var maxDrawdown = Decimal.zero;

    for (final date in dates) {
      for (final allocation in normalized) {
        final points = series[allocation.symbol];
        if (points == null) continue;
        var nextIndex = nextScheduleBySymbol[allocation.symbol] ?? 0;
        while (nextIndex < schedule.length &&
            !schedule[nextIndex].isAfter(date)) {
          final price = _priceAtOrBefore(points, date);
          if (price != null) {
            final amount = input.amountPerContribution * allocation.weight;
            final quantity = (amount / price.close).toDecimal(
              scaleOnInfinitePrecision: _scale,
            );
            if (quantity > Decimal.zero) {
              contributions.add(
                DcaContribution(
                  asOf: date,
                  symbol: allocation.symbol,
                  amount: amount,
                  price: price.close,
                  quantity: quantity,
                ),
              );
              quantities.update(
                allocation.symbol,
                (value) => value + quantity,
                ifAbsent: () => quantity,
              );
              invested.update(
                allocation.symbol,
                (value) => value + amount,
                ifAbsent: () => amount,
              );
              totalInvested += amount;
            }
          }
          nextIndex += 1;
        }
        nextScheduleBySymbol[allocation.symbol] = nextIndex;
      }

      final value = _portfolioValue(series, quantities, date);
      if (value > Decimal.zero) {
        equityCurve.add(DcaEquityPoint(asOf: date, value: value));
        if (value > peak) peak = value;
        if (peak > Decimal.zero) {
          final drawdown = ((peak - value) / peak).toDecimal(
            scaleOnInfinitePrecision: _scale,
          );
          if (drawdown > maxDrawdown) maxDrawdown = drawdown;
        }
      }
    }

    if (contributions.isEmpty || totalInvested == Decimal.zero) {
      return _empty(input.currency);
    }

    final positions = [
      for (final allocation in normalized)
        if ((quantities[allocation.symbol] ?? Decimal.zero) > Decimal.zero)
          _position(
            allocation.symbol,
            series[allocation.symbol]!,
            quantities[allocation.symbol]!,
            invested[allocation.symbol]!,
          ),
    ];
    final endingValue = positions.fold<Decimal>(
      Decimal.zero,
      (sum, position) => sum + position.endingValue,
    );
    final totalQuantity = positions.fold<Decimal>(
      Decimal.zero,
      (sum, position) => sum + position.quantity,
    );
    final averageCost = totalQuantity == Decimal.zero
        ? Decimal.zero
        : (totalInvested / totalQuantity).toDecimal(
            scaleOnInfinitePrecision: _scale,
          );
    final cumulativeReturn = ((endingValue - totalInvested) / totalInvested)
        .toDecimal(scaleOnInfinitePrecision: _scale);

    return DcaSimulationResult(
      currency: input.currency,
      contributions: List.unmodifiable(contributions),
      positions: List.unmodifiable(positions),
      equityCurve: List.unmodifiable(equityCurve),
      totalInvested: totalInvested,
      endingValue: endingValue,
      cumulativeReturn: cumulativeReturn,
      averageCost: averageCost,
      maxDrawdown: maxDrawdown,
    );
  }

  DcaPositionResult _position(
    String symbol,
    List<DcaPricePoint> points,
    Decimal quantity,
    Decimal invested,
  ) {
    final last = points.last;
    final endingValue = quantity * last.close;
    final averageCost = (invested / quantity).toDecimal(
      scaleOnInfinitePrecision: _scale,
    );
    return DcaPositionResult(
      symbol: symbol,
      quantity: quantity,
      invested: invested,
      endingValue: endingValue,
      averageCost: averageCost,
    );
  }

  static DcaSimulationResult _empty(String currency) => DcaSimulationResult(
    currency: currency,
    contributions: const [],
    positions: const [],
    equityCurve: const [],
    totalInvested: Decimal.zero,
    endingValue: Decimal.zero,
    cumulativeReturn: Decimal.zero,
    averageCost: Decimal.zero,
    maxDrawdown: Decimal.zero,
  );
}

List<DcaAllocation> _normalizeAllocations(List<DcaAllocation> allocations) {
  final cleaned = [
    for (final allocation in allocations)
      if (allocation.symbol.trim().isNotEmpty &&
          allocation.weight > Decimal.zero)
        DcaAllocation(
          symbol: allocation.symbol.trim().toUpperCase(),
          weight: allocation.weight,
        ),
  ];
  final total = cleaned.fold<Decimal>(
    Decimal.zero,
    (sum, allocation) => sum + allocation.weight,
  );
  if (total <= Decimal.zero) return const [];
  return [
    for (final allocation in cleaned)
      DcaAllocation(
        symbol: allocation.symbol,
        weight: (allocation.weight / total).toDecimal(
          scaleOnInfinitePrecision: _scale,
        ),
      ),
  ];
}

List<DateTime> _unionDates(Iterable<List<DcaPricePoint>> series) {
  final dates = <DateTime>{};
  for (final points in series) {
    dates.addAll(points.map((p) => _month(p.asOf)));
  }
  return dates.toList()..sort();
}

List<DateTime> _schedule(DateTime from, DateTime to, DcaFrequency frequency) {
  final months = frequency == DcaFrequency.monthly ? 1 : 3;
  final out = <DateTime>[];
  var cursor = _month(from);
  final end = _month(to);
  while (!cursor.isAfter(end)) {
    out.add(cursor);
    cursor = DateTime.utc(cursor.year, cursor.month + months);
  }
  return out;
}

DcaPricePoint? _priceAtOrBefore(List<DcaPricePoint> points, DateTime date) {
  DcaPricePoint? candidate;
  final month = _month(date);
  for (final point in points) {
    if (_month(point.asOf).isAfter(month)) break;
    candidate = point;
  }
  return candidate;
}

Decimal _portfolioValue(
  Map<String, List<DcaPricePoint>> series,
  Map<String, Decimal> quantities,
  DateTime date,
) {
  var value = Decimal.zero;
  for (final entry in quantities.entries) {
    final qty = entry.value;
    if (qty <= Decimal.zero) continue;
    final points = series[entry.key];
    if (points == null) continue;
    final price = _priceAtOrBefore(points, date);
    if (price != null) value += qty * price.close;
  }
  return value;
}

DateTime _month(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month);
}
