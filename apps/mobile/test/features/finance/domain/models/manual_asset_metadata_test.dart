import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';

void main() {
  test('CashMetadata roundtrips through encode/decode', () {
    const meta = CashMetadata(accountId: 'acc-1');
    final decoded = ManualAssetMetadata.decode(meta.encode());
    expect(decoded, isA<CashMetadata>());
    expect((decoded! as CashMetadata).accountId, 'acc-1');
  });

  test('DepositMetadata preserves Decimal precision and dates', () {
    final meta = DepositMetadata(
      accountId: 'acc-1',
      principal: Decimal.parse('123456.7890'),
      interestRate: Decimal.parse('0.0325'),
      startDate: DateTime.utc(2026, 4, 1),
      maturityDate: DateTime.utc(2027, 4, 1),
      autoRenew: true,
    );
    final decoded =
        ManualAssetMetadata.decode(meta.encode())! as DepositMetadata;
    expect(decoded.principal, Decimal.parse('123456.7890'));
    expect(decoded.interestRate, Decimal.parse('0.0325'));
    expect(decoded.startDate, DateTime.utc(2026, 4, 1));
    expect(decoded.maturityDate, DateTime.utc(2027, 4, 1));
    expect(decoded.autoRenew, isTrue);
  });

  test('WealthProductMetadata roundtrips with optional fields null', () {
    final meta = WealthProductMetadata(
      accountId: 'acc-1',
      principal: Decimal.parse('50000'),
      expectedAnnualReturn: Decimal.parse('0.045'),
    );
    final decoded =
        ManualAssetMetadata.decode(meta.encode())! as WealthProductMetadata;
    expect(decoded.principal, Decimal.parse('50000'));
    expect(decoded.expectedAnnualReturn, Decimal.parse('0.045'));
    expect(decoded.issuer, isNull);
    expect(decoded.productCode, isNull);
    expect(decoded.startDate, isNull);
  });

  test('decode returns null for empty / malformed JSON', () {
    expect(ManualAssetMetadata.decode(null), isNull);
    expect(ManualAssetMetadata.decode(''), isNull);
    expect(ManualAssetMetadata.decode('{"kind":"unknown"}'), isNull);
  });
}
