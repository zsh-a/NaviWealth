import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/accounts/domain/account_balances.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/manual_asset_metadata.dart';
import 'package:naviwealth/features/options_income/application/scan_inputs_bridge.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 1),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

Asset _asset({
  required String id,
  required AssetType type,
  required String currency,
  String? accountId,
}) => Asset(
  id: id,
  type: type,
  symbol: id,
  currency: currency,
  metadataJson: accountId == null
      ? null
      : CashMetadata(accountId: accountId).encode(),
  sync: _meta(),
);

AccountBalances _balances(String accountId, String unit, String units) =>
    AccountBalances(
      accountId: accountId,
      legs: [AccountBalanceLeg(unit: unit, units: Decimal.parse(units))],
    );

void main() {
  group('optionsAvailableCashFromBalances', () {
    test('sums real USD cash balances from linked cash assets', () {
      final cash = optionsAvailableCashFromBalances(
        manualAssets: [
          _asset(
            id: 'cash-usd',
            type: AssetType.cash,
            currency: 'USD',
            accountId: 'acc-usd',
          ),
          _asset(
            id: 'cash-cny',
            type: AssetType.cash,
            currency: 'CNY',
            accountId: 'acc-cny',
          ),
          _asset(
            id: 'deposit-usd',
            type: AssetType.bankDepositDemand,
            currency: 'USD',
            accountId: 'acc-deposit',
          ),
        ],
        balancesByAccountId: {
          'acc-usd': _balances('acc-usd', 'USD', '25000'),
          'acc-cny': _balances('acc-cny', 'CNY', '100000'),
          'acc-deposit': _balances('acc-deposit', 'USD', '999999'),
        },
      );

      expect(cash, Money.parse('25000', 'USD'));
    });

    test('deduplicates cash assets pointing at the same account', () {
      final cash = optionsAvailableCashFromBalances(
        manualAssets: [
          _asset(
            id: 'cash-a',
            type: AssetType.cash,
            currency: 'USD',
            accountId: 'acc-usd',
          ),
          _asset(
            id: 'cash-b',
            type: AssetType.cash,
            currency: 'USD',
            accountId: 'acc-usd',
          ),
        ],
        balancesByAccountId: {'acc-usd': _balances('acc-usd', 'USD', '100')},
      );

      expect(cash, Money.parse('100', 'USD'));
    });

    test('floors negative total cash at zero', () {
      final cash = optionsAvailableCashFromBalances(
        manualAssets: [
          _asset(
            id: 'cash-usd',
            type: AssetType.cash,
            currency: 'USD',
            accountId: 'acc-usd',
          ),
        ],
        balancesByAccountId: {'acc-usd': _balances('acc-usd', 'USD', '-50')},
      );

      expect(cash, Money.zero('USD'));
    });
  });
}
