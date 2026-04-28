import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset_meta.dart';

void main() {
  group('PhysicalAssetMeta', () {
    test('round-trips encode/decode for real estate fields', () {
      final meta = PhysicalAssetMeta(
        address: '123 Main St',
        purchaseDate: DateTime.utc(2024, 1, 15),
        purchasePrice: Decimal.parse('1500000.00'),
        linkedLiabilityId: 'liab-1',
      );
      final decoded = PhysicalAssetMeta.tryDecode(meta.encode())!;
      expect(decoded.address, '123 Main St');
      expect(decoded.purchaseDate, DateTime.utc(2024, 1, 15));
      expect(decoded.purchasePrice, Decimal.parse('1500000.00'));
      expect(decoded.linkedLiabilityId, 'liab-1');
      expect(decoded.autoDepreciation, isFalse);
      expect(decoded.annualResidualRate, isNull);
    });

    test('round-trips vehicle fields', () {
      final meta = PhysicalAssetMeta(
        purchaseDate: DateTime.utc(2023, 6, 1),
        purchasePrice: Decimal.parse('250000.5'),
        annualResidualRate: Decimal.parse('0.85'),
        autoDepreciation: true,
      );
      final decoded = PhysicalAssetMeta.tryDecode(meta.encode())!;
      expect(decoded.annualResidualRate, Decimal.parse('0.85'));
      expect(decoded.autoDepreciation, isTrue);
      expect(decoded.address, isNull);
      expect(decoded.linkedLiabilityId, isNull);
    });

    test('preserves unknown future keys on round-trip', () {
      // A newer client wrote the row with a `wear_level` field; we must
      // re-emit it on encode so we don't trash data on edit.
      const raw =
          '{"purchase_date":"2024-01-01T00:00:00Z","purchase_price":"100",'
          '"auto_depreciation":false,"wear_level":"moderate"}';
      final decoded = PhysicalAssetMeta.tryDecode(raw)!;
      expect(decoded.extra, containsPair('wear_level', 'moderate'));
      final encoded = decoded.encode();
      expect(encoded.contains('"wear_level":"moderate"'), isTrue);
    });

    test('returns null for malformed JSON', () {
      expect(PhysicalAssetMeta.tryDecode('not-json'), isNull);
      expect(PhysicalAssetMeta.tryDecode(null), isNull);
      expect(PhysicalAssetMeta.tryDecode(''), isNull);
    });

    test('returns null for missing required fields', () {
      // Missing purchase_price.
      const raw = '{"purchase_date":"2024-01-01T00:00:00Z"}';
      expect(() => PhysicalAssetMeta.tryDecode(raw), throwsFormatException);
    });

    test('copyWith preserves untouched fields and supports null clears', () {
      final meta = PhysicalAssetMeta(
        address: '123 Main St',
        purchaseDate: DateTime.utc(2024, 1, 15),
        purchasePrice: Decimal.fromInt(100),
        linkedLiabilityId: 'liab-1',
      );
      final updated = meta.copyWith(linkedLiabilityId: null);
      expect(updated.linkedLiabilityId, isNull);
      expect(updated.address, '123 Main St');
      expect(updated.purchasePrice, Decimal.fromInt(100));

      final renamed = meta.copyWith(address: 'New');
      expect(renamed.address, 'New');
      expect(renamed.linkedLiabilityId, 'liab-1');
    });
  });
}
