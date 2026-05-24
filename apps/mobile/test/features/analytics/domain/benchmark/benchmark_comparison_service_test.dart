import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_comparison.dart';
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_index.dart';

DateTime _d(int year, int month, int day) => DateTime.utc(year, month, day);

Matcher _closeTo(double v, [double eps = 1e-6]) =>
    inInclusiveRange(v - eps, v + eps);

void main() {
  const service = BenchmarkComparisonService();

  test('catalogue covers every BenchmarkIndex enum value', () {
    for (final index in BenchmarkIndex.values) {
      final info = benchmarkInfoFor(index);
      expect(info.index, index);
      expect(info.symbol, isNotEmpty);
      expect(info.currency.length, 3);
    }
  });

  test(
    'normalizes the portfolio curve to 1.0 at the first in-window point',
    () {
      final result = service.compute(
        from: _d(2025, 1, 1),
        to: _d(2025, 12, 31),
        portfolio: [
          TimeSeriesPoint(asOf: _d(2025, 1, 1), value: 1000),
          TimeSeriesPoint(asOf: _d(2025, 7, 1), value: 1100),
          TimeSeriesPoint(asOf: _d(2025, 12, 31), value: 1200),
        ],
        benchmarks: const {},
      );

      expect(result.portfolioPoints, hasLength(3));
      expect(result.portfolioPoints[0].value, _closeTo(1.0));
      expect(result.portfolioPoints[1].value, _closeTo(1.1));
      expect(result.portfolioPoints[2].value, _closeTo(1.2));
    },
  );

  test('drops points outside [from, to] before normalizing', () {
    final result = service.compute(
      from: _d(2025, 6, 1),
      to: _d(2025, 12, 31),
      portfolio: [
        TimeSeriesPoint(asOf: _d(2024, 12, 1), value: 500),
        TimeSeriesPoint(asOf: _d(2025, 6, 1), value: 1000),
        TimeSeriesPoint(asOf: _d(2025, 12, 31), value: 1500),
        TimeSeriesPoint(asOf: _d(2026, 1, 1), value: 9999),
      ],
      benchmarks: const {},
    );

    expect(result.portfolioPoints, hasLength(2));
    expect(result.portfolioPoints.first.value, _closeTo(1.0));
    expect(result.portfolioPoints.last.value, _closeTo(1.5));
  });

  test('annualizedReturn computes CAGR to 365.25 day count', () {
    // 1000 → 1100 over exactly 365 calendar days ⇒ ~10.027% CAGR.
    final result = service.compute(
      from: _d(2024, 1, 1),
      to: _d(2024, 12, 31),
      portfolio: [
        TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 1000),
        TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 1100),
      ],
      benchmarks: const {},
    );
    expect(result.portfolioAnnualizedReturn, _closeTo(0.10028, 1e-3));
  });

  test('returns null annualized when window is empty or degenerate', () {
    expect(
      service
          .compute(
            from: _d(2024, 1, 1),
            to: _d(2024, 1, 1),
            portfolio: [TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 100)],
            benchmarks: const {},
          )
          .portfolioAnnualizedReturn,
      isNull,
    );
    expect(
      service
          .compute(
            from: _d(2024, 1, 1),
            to: _d(2024, 12, 31),
            portfolio: const [],
            benchmarks: const {},
          )
          .portfolioAnnualizedReturn,
      isNull,
    );
  });

  test('excessReturnFor subtracts benchmark from portfolio annualized', () {
    final result = service.compute(
      from: _d(2024, 1, 1),
      to: _d(2024, 12, 31),
      portfolio: [
        TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 1000),
        TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 1200),
      ],
      benchmarks: {
        BenchmarkIndex.sp500: [
          TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 4500),
          TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 4950),
        ],
      },
    );
    final excess = result.excessReturnFor(BenchmarkIndex.sp500);
    expect(excess, isNotNull);
    // ~20% portfolio − ~10% benchmark ≈ +10pp.
    expect(excess!, _closeTo(0.10, 5e-3));
  });

  test('excessReturnFor returns null if either side is missing', () {
    final result = service.compute(
      from: _d(2024, 1, 1),
      to: _d(2024, 12, 31),
      portfolio: [
        TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 1000),
        TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 1200),
      ],
      benchmarks: const {BenchmarkIndex.hs300: []},
    );
    expect(result.excessReturnFor(BenchmarkIndex.hs300), isNull);
  });

  test('overridePortfolioAnnualizedReturn replaces the headline CAGR', () {
    final result = service.compute(
      from: _d(2024, 1, 1),
      to: _d(2024, 12, 31),
      portfolio: [
        TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 1000),
        TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 1100),
      ],
      benchmarks: const {},
      overridePortfolioAnnualizedReturn: 0.42,
    );
    expect(result.portfolioAnnualizedReturn, 0.42);
  });

  test('preserves benchmark order from the order list', () {
    final result = service.compute(
      from: _d(2024, 1, 1),
      to: _d(2024, 12, 31),
      portfolio: const [],
      benchmarks: {
        BenchmarkIndex.sp500: [
          TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 100),
          TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 110),
        ],
        BenchmarkIndex.hs300: [
          TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 200),
          TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 220),
        ],
      },
      order: const [BenchmarkIndex.hs300, BenchmarkIndex.sp500],
    );
    expect(result.benchmarks.map((b) => b.index).toList(), const [
      BenchmarkIndex.hs300,
      BenchmarkIndex.sp500,
    ]);
  });

  test('rejects non-positive base values', () {
    final result = service.compute(
      from: _d(2024, 1, 1),
      to: _d(2024, 12, 31),
      portfolio: [
        TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 0),
        TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 100),
      ],
      benchmarks: const {},
    );
    expect(result.portfolioPoints, isEmpty);
    expect(result.portfolioAnnualizedReturn, isNull);
  });

  test('handles unsorted input deterministically', () {
    final result = service.compute(
      from: _d(2024, 1, 1),
      to: _d(2024, 12, 31),
      portfolio: [
        TimeSeriesPoint(asOf: _d(2024, 12, 31), value: 1200),
        TimeSeriesPoint(asOf: _d(2024, 6, 1), value: 1100),
        TimeSeriesPoint(asOf: _d(2024, 1, 1), value: 1000),
      ],
      benchmarks: const {},
    );
    expect(result.portfolioPoints.first.asOf, _d(2024, 1, 1));
    expect(result.portfolioPoints.last.asOf, _d(2024, 12, 31));
  });
}
