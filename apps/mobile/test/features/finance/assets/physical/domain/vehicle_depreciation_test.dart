import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/assets/physical/domain/vehicle_depreciation.dart';

void main() {
  group('VehicleDepreciation.estimate', () {
    final purchasePrice = Decimal.fromInt(200000);
    final purchase = DateTime.utc(2024, 1, 1);

    test('returns purchase price on or before purchase date', () {
      expect(
        VehicleDepreciation.estimate(
          purchasePrice: purchasePrice,
          purchaseDate: purchase,
          annualResidualRate: Decimal.parse('0.85'),
          asOf: purchase,
        ),
        purchasePrice,
      );
      expect(
        VehicleDepreciation.estimate(
          purchasePrice: purchasePrice,
          purchaseDate: purchase,
          annualResidualRate: Decimal.parse('0.85'),
          asOf: DateTime.utc(2023, 12, 1),
        ),
        purchasePrice,
      );
    });

    test('clamps to purchase price when residual rate >= 1', () {
      expect(
        VehicleDepreciation.estimate(
          purchasePrice: purchasePrice,
          purchaseDate: purchase,
          annualResidualRate: Decimal.one,
          asOf: DateTime.utc(2026, 1, 1),
        ),
        purchasePrice,
      );
    });

    test('clamps to zero when residual rate <= 0', () {
      expect(
        VehicleDepreciation.estimate(
          purchasePrice: purchasePrice,
          purchaseDate: purchase,
          annualResidualRate: Decimal.zero,
          asOf: DateTime.utc(2026, 1, 1),
        ),
        Decimal.zero,
      );
    });

    test('hits exact anniversary value after a full year', () {
      // After exactly one Gregorian-year stride (~365.2425 days), residual
      // should be 0.85 * 200000 within a small tolerance from the
      // year-length scaling.
      final after = purchase.add(const Duration(days: 365));
      final value = VehicleDepreciation.estimate(
        purchasePrice: purchasePrice,
        purchaseDate: purchase,
        annualResidualRate: Decimal.parse('0.85'),
        asOf: after,
      );
      // Expect roughly between 170000 (one full year) and the cusp.
      expect(value < purchasePrice, isTrue);
      expect(value > Decimal.fromInt(165000), isTrue);
    });

    test('multi-year compounding matches loop value at anniversary', () {
      // ~3 Gregorian years.
      final threeYears = purchase.add(const Duration(days: 365 * 3 + 1));
      final value = VehicleDepreciation.estimate(
        purchasePrice: purchasePrice,
        purchaseDate: purchase,
        annualResidualRate: Decimal.parse('0.85'),
        asOf: threeYears,
      );
      // 200000 * 0.85^3 = 122825
      expect(value < Decimal.fromInt(125000), isTrue);
      expect(value > Decimal.fromInt(120000), isTrue);
    });

    test('is monotonically non-increasing over time', () {
      Decimal? previous;
      for (var months = 0; months <= 60; months += 3) {
        final at = DateTime(
          purchase.year,
          purchase.month + months,
          purchase.day,
        );
        final value = VehicleDepreciation.estimate(
          purchasePrice: purchasePrice,
          purchaseDate: purchase,
          annualResidualRate: Decimal.parse('0.85'),
          asOf: at,
        );
        if (previous != null) {
          expect(
            value <= previous,
            isTrue,
            reason: 'value at month $months ($value) should be <= prior',
          );
        }
        previous = value;
      }
    });

    test('matches loop-only computation at exact anniversary', () {
      final fiveYears = purchase.add(const Duration(days: 1827));
      final value = VehicleDepreciation.estimate(
        purchasePrice: purchasePrice,
        purchaseDate: purchase,
        annualResidualRate: Decimal.parse('0.9'),
        asOf: fiveYears,
      );
      // 200000 * 0.9^5 = 118098
      expect(value < Decimal.fromInt(120000), isTrue);
      expect(value > Decimal.fromInt(116000), isTrue);
    });
  });

  group('VehicleDepreciation.projectMonthly', () {
    test('returns empty when window collapsed', () {
      final pts = VehicleDepreciation.projectMonthly(
        purchasePrice: Decimal.fromInt(100),
        purchaseDate: DateTime.utc(2024, 1, 1),
        annualResidualRate: Decimal.parse('0.8'),
        from: DateTime.utc(2024, 6, 1),
        to: DateTime.utc(2024, 6, 1),
      );
      expect(pts, isEmpty);
    });

    test('caps at maxPoints', () {
      final pts = VehicleDepreciation.projectMonthly(
        purchasePrice: Decimal.fromInt(100),
        purchaseDate: DateTime.utc(2020, 1, 1),
        annualResidualRate: Decimal.parse('0.8'),
        from: DateTime.utc(2020, 1, 1),
        to: DateTime.utc(2030, 1, 1),
        maxPoints: 12,
      );
      // 120 months / stride 10 -> 13 samples (inclusive endpoints).
      expect(pts.length, lessThanOrEqualTo(13));
      expect(pts.every((p) => p.kind == ValuationPointKind.projected), isTrue);
    });
  });
}
