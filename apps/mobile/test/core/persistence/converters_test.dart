import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/converters.dart';
import 'package:naviwealth/core/persistence/domain_enums.dart';
import 'package:naviwealth/core/sync/hlc.dart';

void main() {
  group('DecimalConverter', () {
    test('stores exact base-10 text without double conversion', () {
      const converter = DecimalConverter();
      final value = Decimal.parse('1234567890.123456789012345678');

      final sql = converter.toSql(value);

      expect(sql, '1234567890.123456789012345678');
      expect(converter.fromSql(sql), value);
    });
  });

  group('HlcConverter', () {
    test('round-trips the canonical HLC wire form', () {
      const converter = HlcConverter();
      final hlc = Hlc.parse('1716400000000.000a-device-a');

      final sql = converter.toSql(hlc);

      expect(sql, '1716400000000.000a-device-a');
      expect(converter.fromSql(sql), hlc);
    });
  });

  group('EnumStringConverter', () {
    test('persists enum names rather than ordinal indexes', () {
      const converter = EnumStringConverter(AccountCategory.values);

      expect(converter.toSql(AccountCategory.broker), 'broker');
      expect(converter.fromSql('broker'), AccountCategory.broker);
    });

    test('rejects unknown persisted enum labels', () {
      const converter = EnumStringConverter(AssetType.values);

      expect(() => converter.fromSql('legacy_unknown'), throwsArgumentError);
    });
  });

  group('domain enum classifications', () {
    test('manual valuation and security asset buckets do not overlap', () {
      expect(
        kManualValuationAssetTypes.intersection(kSecuritiesAssetTypes),
        isEmpty,
      );
    });

    test('account categories map to stable accounting sides', () {
      expect(accountSideForCategory(AccountCategory.cash), AccountSide.asset);
      expect(accountSideForCategory(AccountCategory.bank), AccountSide.asset);
      expect(accountSideForCategory(AccountCategory.broker), AccountSide.asset);
      expect(accountSideForCategory(AccountCategory.crypto), AccountSide.asset);
      expect(accountSideForCategory(AccountCategory.asset), AccountSide.asset);
      expect(
        accountSideForCategory(AccountCategory.credit),
        AccountSide.liability,
      );
      expect(
        accountSideForCategory(AccountCategory.loan),
        AccountSide.liability,
      );
      expect(
        accountSideForCategory(AccountCategory.liability),
        AccountSide.liability,
      );
    });
  });
}
