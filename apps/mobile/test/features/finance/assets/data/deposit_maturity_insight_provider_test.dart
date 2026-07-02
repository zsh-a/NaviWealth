import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/assets/data/deposit_maturity_insight_provider.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/manual_asset_metadata.dart';

void main() {
  group('summarizeDepositMaturities', () {
    test('returns the count and nearest maturity inside the alert window', () {
      final summary = summarizeDepositMaturities(
        assets: [
          _termDeposit(id: 'later', maturityDate: DateTime.utc(2026, 6, 14)),
          _termDeposit(id: 'nearest', maturityDate: DateTime.utc(2026, 6, 4)),
          _termDeposit(id: 'today', maturityDate: DateTime.utc(2026, 6, 1)),
        ],
        now: DateTime.utc(2026, 6, 1, 23, 59),
      );

      expect(summary, isNotNull);
      expect(summary!.count, 3);
      expect(summary.days, 0);
    });

    test('ignores expired, out-of-window, demand, and untyped assets', () {
      final summary = summarizeDepositMaturities(
        assets: [
          _termDeposit(id: 'expired', maturityDate: DateTime.utc(2026, 5, 31)),
          _termDeposit(id: 'too-far', maturityDate: DateTime.utc(2026, 6, 16)),
          _demandDeposit(id: 'demand'),
          _termDeposit(id: 'missing-meta', metadataJson: null),
          _termDeposit(id: 'valid', maturityDate: DateTime.utc(2026, 6, 15)),
        ],
        now: DateTime.utc(2026, 6, 1),
      );

      expect(summary, isNotNull);
      expect(summary!.count, 1);
      expect(summary.days, 14);
    });

    test('returns null when no term deposits mature within the window', () {
      final summary = summarizeDepositMaturities(
        assets: [
          _termDeposit(id: 'too-far', maturityDate: DateTime.utc(2026, 7, 1)),
          _demandDeposit(id: 'demand'),
        ],
        now: DateTime.utc(2026, 6, 1),
      );

      expect(summary, isNull);
    });
  });
}

Asset _termDeposit({
  required String id,
  DateTime? maturityDate,
  String? metadataJson,
}) => Asset(
  id: id,
  type: AssetType.bankDepositTerm,
  symbol: id,
  currency: 'CNY',
  metadataJson:
      metadataJson ??
      DepositMetadata(
        accountId: 'acc-$id',
        principal: Decimal.parse('10000'),
        interestRate: Decimal.parse('0.025'),
        startDate: DateTime.utc(2026, 1, 1),
        maturityDate: maturityDate,
      ).encode(),
  sync: _meta(),
);

Asset _demandDeposit({required String id}) => Asset(
  id: id,
  type: AssetType.bankDepositDemand,
  symbol: id,
  currency: 'CNY',
  metadataJson: DepositMetadata(
    accountId: 'acc-$id',
    principal: Decimal.parse('10000'),
    interestRate: Decimal.parse('0.003'),
  ).encode(),
  sync: _meta(),
);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u1',
  updatedAt: DateTime.utc(2026, 6, 1),
  updatedByDevice: 'dev',
  hlc: Hlc.zero('dev'),
);
