import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'benchmark_index.dart';

/// One observation on a normalized return curve. `value` is the ratio of
/// the underlying series at [asOf] over its first observation in the
/// window, expressed as an index level (1.0 == "back at start").
@immutable
class NormalizedReturnPoint {
  const NormalizedReturnPoint({required this.asOf, required this.value});

  final DateTime asOf;
  final double value;
}

/// One benchmark series after normalization, plus the annualized return
/// computed from the same start / end pair.
@immutable
class BenchmarkSeries {
  const BenchmarkSeries({
    required this.index,
    required this.points,
    required this.annualizedReturn,
  });

  final BenchmarkIndex index;
  final List<NormalizedReturnPoint> points;

  /// Annualized return over the window, expressed as a decimal (`0.12 =
  /// 12%`). `null` when the window is too short or no data was available
  /// — callers should render the dash placeholder rather than 0%.
  final double? annualizedReturn;
}

/// Result returned by [BenchmarkComparisonService.compute]. Holds the
/// portfolio's normalized curve (always present, possibly empty) plus one
/// [BenchmarkSeries] per benchmark the caller asked for. The order of
/// [benchmarks] matches the input order so the chart can pair colors to
/// chip positions deterministically.
@immutable
class BenchmarkComparisonResult {
  const BenchmarkComparisonResult({
    required this.from,
    required this.to,
    required this.portfolioPoints,
    required this.portfolioAnnualizedReturn,
    required this.benchmarks,
  });

  final DateTime from;
  final DateTime to;
  final List<NormalizedReturnPoint> portfolioPoints;
  final double? portfolioAnnualizedReturn;
  final List<BenchmarkSeries> benchmarks;

  bool get isEmpty =>
      portfolioPoints.isEmpty && benchmarks.every((b) => b.points.isEmpty);

  /// Excess return for [index]: `portfolio − benchmark`. `null` when
  /// either side is missing — the UI renders an "—" placeholder.
  double? excessReturnFor(BenchmarkIndex index) {
    final port = portfolioAnnualizedReturn;
    final bench = _seriesFor(index)?.annualizedReturn;
    if (port == null || bench == null) return null;
    return port - bench;
  }

  BenchmarkSeries? _seriesFor(BenchmarkIndex index) {
    for (final b in benchmarks) {
      if (b.index == index) return b;
    }
    return null;
  }
}

/// Raw `(date, value)` row used as input to the service. Generic so the
/// portfolio path (Money over time) and benchmark prices (Decimal close)
/// can both be projected through the same code with a single conversion
/// at the boundary.
@immutable
class TimeSeriesPoint {
  const TimeSeriesPoint({required this.asOf, required this.value});

  final DateTime asOf;
  final double value;
}

/// Pure domain service — no IO, no state. Given the portfolio path and a
/// map of benchmark price paths, returns a [BenchmarkComparisonResult]
/// the UI can render directly. Each path is normalized independently to
/// `1.0` at its first observed point in the window so visual scale is
/// comparable across mixed-currency benchmarks (HSI in HKD vs S&P in USD).
///
/// Annualized return follows the standard compounded-growth formula:
///
///     cagr = (end / start) ^ (365.25 / windowDays) − 1
///
/// computed on the price path only — i.e. ignoring portfolio cash flows.
/// For the portfolio side this is the "absolute return" branch the XIRR
/// engine falls back to when there are too few flows; once the
/// postings-derived return read model is wired through Riverpod, the
/// caller can pass that value in via [overridePortfolioAnnualizedReturn]
/// and the chart will keep using the net-worth curve for visualisation
/// while showing the XIRR as the headline number.
class BenchmarkComparisonService {
  const BenchmarkComparisonService();

  /// Days per year used for annualization. Matches the actual/365.25 day
  /// count the rest of the platform uses (XIRR engine, FIRE projector).
  static const double _daysPerYear = 365.25;

  BenchmarkComparisonResult compute({
    required DateTime from,
    required DateTime to,
    required List<TimeSeriesPoint> portfolio,
    required Map<BenchmarkIndex, List<TimeSeriesPoint>> benchmarks,
    List<BenchmarkIndex>? order,
    double? overridePortfolioAnnualizedReturn,
  }) {
    final orderedBenchmarks = order ?? benchmarks.keys.toList();

    final portfolioPoints = _normalize(portfolio, from: from, to: to);
    final portfolioCagr =
        overridePortfolioAnnualizedReturn ??
        _annualizedFromSeries(portfolio, from: from, to: to);

    final results = <BenchmarkSeries>[];
    for (final index in orderedBenchmarks) {
      final raw = benchmarks[index] ?? const <TimeSeriesPoint>[];
      results.add(
        BenchmarkSeries(
          index: index,
          points: _normalize(raw, from: from, to: to),
          annualizedReturn: _annualizedFromSeries(raw, from: from, to: to),
        ),
      );
    }

    return BenchmarkComparisonResult(
      from: from,
      to: to,
      portfolioPoints: portfolioPoints,
      portfolioAnnualizedReturn: portfolioCagr,
      benchmarks: results,
    );
  }

  /// Trim [points] to `[from, to]` (inclusive) and rescale so the first
  /// in-range point has `value = 1.0`. Returns `[]` when no in-range point
  /// has a positive base value.
  List<NormalizedReturnPoint> _normalize(
    List<TimeSeriesPoint> points, {
    required DateTime from,
    required DateTime to,
  }) {
    if (points.isEmpty) return const [];
    final inRange = [
      for (final p in points)
        if (!p.asOf.isBefore(from) && !p.asOf.isAfter(to)) p,
    ]..sort((a, b) => a.asOf.compareTo(b.asOf));
    if (inRange.isEmpty) return const [];
    final base = inRange.first.value;
    if (base <= 0 || !base.isFinite) return const [];
    return [
      for (final p in inRange)
        NormalizedReturnPoint(asOf: p.asOf, value: p.value / base),
    ];
  }

  double? _annualizedFromSeries(
    List<TimeSeriesPoint> points, {
    required DateTime from,
    required DateTime to,
  }) {
    if (points.isEmpty) return null;
    final inRange = [
      for (final p in points)
        if (!p.asOf.isBefore(from) && !p.asOf.isAfter(to)) p,
    ]..sort((a, b) => a.asOf.compareTo(b.asOf));
    if (inRange.length < 2) return null;
    final start = inRange.first;
    final end = inRange.last;
    if (start.value <= 0 || !start.value.isFinite) return null;
    if (end.value <= 0 || !end.value.isFinite) return null;
    final spanDays = end.asOf.difference(start.asOf).inDays;
    if (spanDays <= 0) return null;
    final years = spanDays / _daysPerYear;
    if (years <= 0) return null;
    final ratio = end.value / start.value;
    final cagr = math.pow(ratio, 1.0 / years).toDouble() - 1;
    if (cagr.isNaN || !cagr.isFinite) return null;
    return cagr;
  }
}
