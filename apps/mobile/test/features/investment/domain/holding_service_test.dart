import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/enums.dart' hide CostBasisMethod;
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/domain/transaction.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/investment/domain/cost_basis/cost_basis_method.dart';
import 'package:naviwealth/features/investment/domain/holding_price_source.dart';
import 'package:naviwealth/features/investment/domain/holding_service.dart';
import 'package:naviwealth/features/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';

import '_helpers.dart';

const _user = 'user-1';

Transaction _tx({
  required String id,
  required TransactionType type,
  required String accountId,
  required String? assetId,
  required Decimal quantity,
  required Decimal price,
  required String currency,
  required DateTime tradeDate,
  Decimal? fee,
  String owner = _user,
  DateTime? deletedAt,
}) {
  return Transaction(
    id: id,
    accountId: accountId,
    assetId: assetId,
    type: type,
    quantity: quantity,
    price: price,
    currency: currency,
    tradeDate: tradeDate,
    fee: fee,
    sync: SyncMeta(
      ownerUserId: owner,
      updatedAt: tradeDate,
      updatedByDevice: 'dev-1',
      hlc: Hlc.zero('node-1'),
      deletedAt: deletedAt,
    ),
  );
}

DefaultHoldingService _service({
  required InMemoryHoldingTransactionsRepository repo,
  required HoldingPriceSource prices,
  HoldingDailySnapshotStore? store,
  CurrencyConverter? converter,
  String baseCurrency = 'USD',
  String Function()? idGenerator,
}) {
  return DefaultHoldingService(
    ownerUserId: _user,
    baseCurrency: baseCurrency,
    costBasisMethod: CostBasisMethod.fifo,
    transactions: repo,
    snapshots: store ?? InMemoryHoldingDailySnapshotStore(),
    prices: prices,
    converter:
        converter ?? FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
    idGenerator: idGenerator,
  );
}

void main() {
  group('DefaultHoldingService.computeAt', () {
    test('with no snapshot, replays the full transaction history', () async {
      final repo = InMemoryHoldingTransactionsRepository(
        transactions: [
          _tx(
            id: 'tx-1',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('10'),
            price: d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
          ),
          _tx(
            id: 'tx-2',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('5'),
            price: d('200'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 2, 1),
          ),
        ],
      );
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('150'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      final svc = _service(repo: repo, prices: prices);

      final result = await svc.computeAt(DateTime.utc(2026, 4, 1));

      // 15 shares total, cost basis $1000 + $1000 = $2000, mv = $2250.
      final aapl = result['AAPL']!;
      expect(aapl.quantity, d('15'));
      expect(aapl.costBasisInBase, d('2000'));
      expect(aapl.marketValueInBase, d('2250'));
      expect(aapl.unrealizedPnlInBase, d('250'));
      expect(aapl.weight, d('1'));
    });

    test('only transactions with tradeDate <= asOf are included', () async {
      final repo = InMemoryHoldingTransactionsRepository(
        transactions: [
          _tx(
            id: 'tx-past',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('10'),
            price: d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
          ),
          _tx(
            id: 'tx-future',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('99'),
            price: d('999'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 6, 1),
          ),
        ],
      );
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('150'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 1, 5),
        ),
      ]);
      final svc = _service(repo: repo, prices: prices);

      final result = await svc.computeAt(DateTime.utc(2026, 4, 1));

      // Only the first tx counts; second is in the future from asOf.
      expect(result['AAPL']!.quantity, d('10'));
    });

    test('soft-deleted transactions are skipped', () async {
      final repo = InMemoryHoldingTransactionsRepository(
        transactions: [
          _tx(
            id: 'tx-deleted',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('99'),
            price: d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
            deletedAt: DateTime.utc(2026, 1, 6),
          ),
          _tx(
            id: 'tx-live',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('10'),
            price: d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 7),
          ),
        ],
      );
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('150'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      final svc = _service(repo: repo, prices: prices);

      final result = await svc.computeAt(DateTime.utc(2026, 4, 1));
      expect(result['AAPL']!.quantity, d('10'));
    });

    test('other users\' transactions are isolated by ownerUserId', () async {
      final repo = InMemoryHoldingTransactionsRepository(
        transactions: [
          _tx(
            id: 'tx-other',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('99'),
            price: d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
            owner: 'other-user',
          ),
          _tx(
            id: 'tx-mine',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('10'),
            price: d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 6),
          ),
        ],
      );
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('100'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 4, 1),
        ),
      ]);
      final svc = _service(repo: repo, prices: prices);

      final result = await svc.computeAt(DateTime.utc(2026, 4, 1));
      expect(result['AAPL']!.quantity, d('10'));
    });
  });

  group('DefaultHoldingService — daily snapshot caching', () {
    test('persistDailySnapshot stores the lot inventory at end of day, '
        'subsequent computeAt replays only the gap', () async {
      final repo = InMemoryHoldingTransactionsRepository(
        transactions: [
          _tx(
            id: 'tx-1',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: d('10'),
            price: d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 5),
          ),
        ],
      );
      final prices = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: d('150'),
          currency: 'USD',
          asOf: DateTime.utc(2026, 1, 31),
        ),
      ]);
      final store = InMemoryHoldingDailySnapshotStore();
      final svc = _service(repo: repo, prices: prices, store: store);

      // Snapshot Jan 31 — 10 shares of AAPL.
      final snap = await svc.persistDailySnapshot(DateTime.utc(2026, 1, 31));
      expect(snap.day, DateTime.utc(2026, 1, 31));
      expect(snap.lots, hasLength(1));
      expect(snap.lots.single.remainingQuantity, d('10'));

      // Now add a backdated tx in the past (already covered by snapshot)
      // and a future tx after the snapshot day. computeAt should replay
      // ONLY the future tx — the past one is captured by the snapshot.
      // We assert by adding a "tripwire" transaction with tradeDate before
      // the snapshot day and confirming it does NOT show up in the result.
      repo.addTransaction(
        _tx(
          // Tripwire: if the service ever replays from epoch, this will
          // double-count the AAPL position.
          id: 'tx-tripwire',
          type: TransactionType.buy,
          accountId: 'a',
          assetId: 'AAPL',
          quantity: d('999'),
          price: d('100'),
          currency: 'USD',
          // Before the snapshot day, so a sound incremental algorithm must
          // treat it as already-folded.
          tradeDate: DateTime.utc(2026, 1, 10),
        ),
      );
      repo.addTransaction(
        _tx(
          id: 'tx-2',
          type: TransactionType.buy,
          accountId: 'a',
          assetId: 'AAPL',
          quantity: d('5'),
          price: d('200'),
          currency: 'USD',
          tradeDate: DateTime.utc(2026, 2, 1),
        ),
      );

      final result = await svc.computeAt(DateTime.utc(2026, 2, 28));
      // Snapshot's 10 + post-snapshot's 5 = 15. The tripwire of 999 is
      // ignored because the snapshot already captured the Jan 5 buy and
      // the service does NOT walk back before the snapshot day.
      expect(result['AAPL']!.quantity, d('15'));
    });

    test(
      'invalidateFrom drops snapshots ≥ a date so they get rebuilt',
      () async {
        final repo = InMemoryHoldingTransactionsRepository(
          transactions: [
            _tx(
              id: 'tx-1',
              type: TransactionType.buy,
              accountId: 'a',
              assetId: 'AAPL',
              quantity: d('10'),
              price: d('100'),
              currency: 'USD',
              tradeDate: DateTime.utc(2026, 1, 5),
            ),
          ],
        );
        final prices = InMemoryHoldingPriceSource([
          HoldingPriceObservation(
            assetId: 'AAPL',
            price: d('150'),
            currency: 'USD',
            asOf: DateTime.utc(2026, 1, 31),
          ),
        ]);
        final store = InMemoryHoldingDailySnapshotStore();
        final svc = _service(repo: repo, prices: prices, store: store);

        // Build snapshots for two consecutive days.
        await svc.persistDailySnapshot(DateTime.utc(2026, 1, 31));
        await svc.persistDailySnapshot(DateTime.utc(2026, 2, 28));

        // Invalidate from Feb 1 — only the Jan 31 snapshot survives.
        await svc.invalidateFrom(DateTime.utc(2026, 2, 1));
        final stillCached = await store.latestOnOrBefore(
          ownerUserId: _user,
          upTo: DateTime.utc(2026, 3, 31),
        );
        expect(stillCached!.day, DateTime.utc(2026, 1, 31));
      },
    );
  });

  group('DefaultHoldingService — corporate actions', () {
    test(
      'a split between snapshot and asOf adjusts the open position',
      () async {
        final repo = InMemoryHoldingTransactionsRepository(
          transactions: [
            _tx(
              id: 'tx-buy',
              type: TransactionType.buy,
              accountId: 'a',
              assetId: 'AAPL',
              quantity: d('100'),
              price: d('200'),
              currency: 'USD',
              tradeDate: DateTime.utc(2026, 1, 5),
            ),
          ],
          corporateActions: [
            SplitAction(
              id: 'split-1',
              assetId: 'AAPL',
              ratio: d('2'),
              effectiveDate: DateTime.utc(2026, 3, 15),
            ),
          ],
        );
        final prices = InMemoryHoldingPriceSource([
          HoldingPriceObservation(
            assetId: 'AAPL',
            price: d('110'), // post-split price
            currency: 'USD',
            asOf: DateTime.utc(2026, 4, 1),
          ),
        ]);
        final svc = _service(repo: repo, prices: prices);

        final result = await svc.computeAt(DateTime.utc(2026, 4, 1));
        // After 2-for-1 split: 200 shares @ cost-per-unit $100, total cost
        // basis $20,000 preserved. MV = 200 * 110 = $22,000.
        final aapl = result['AAPL']!;
        expect(aapl.quantity, d('200'));
        expect(aapl.costBasisInBase, d('20000'));
        expect(aapl.marketValueInBase, d('22000'));
      },
    );
  });

  group('InMemoryHoldingDailySnapshotStore', () {
    test('latestOnOrBefore returns the most recent snapshot ≤ upTo', () async {
      final store = InMemoryHoldingDailySnapshotStore();
      await store.save(
        LotInventorySnapshot(
          ownerUserId: _user,
          day: DateTime.utc(2026, 1, 31),
          lots: const [],
        ),
      );
      await store.save(
        LotInventorySnapshot(
          ownerUserId: _user,
          day: DateTime.utc(2026, 2, 28),
          lots: const [],
        ),
      );

      final mid = await store.latestOnOrBefore(
        ownerUserId: _user,
        upTo: DateTime.utc(2026, 2, 15),
      );
      expect(mid!.day, DateTime.utc(2026, 1, 31));

      final later = await store.latestOnOrBefore(
        ownerUserId: _user,
        upTo: DateTime.utc(2026, 3, 1),
      );
      expect(later!.day, DateTime.utc(2026, 2, 28));

      final earlier = await store.latestOnOrBefore(
        ownerUserId: _user,
        upTo: DateTime.utc(2026, 1, 1),
      );
      expect(earlier, isNull);
    });

    test('save is idempotent for the same (owner, day)', () async {
      final store = InMemoryHoldingDailySnapshotStore();
      await store.save(
        LotInventorySnapshot(
          ownerUserId: _user,
          day: DateTime.utc(2026, 1, 31),
          lots: const [],
        ),
      );
      // Re-save with different lots — must overwrite, not duplicate.
      await store.save(
        LotInventorySnapshot(
          ownerUserId: _user,
          day: DateTime.utc(2026, 1, 31),
          lots: [makeLot(id: 'l-new', remainingQuantity: d('5'))],
        ),
      );
      final got = await store.latestOnOrBefore(
        ownerUserId: _user,
        upTo: DateTime.utc(2026, 12, 31),
      );
      expect(got!.lots, hasLength(1));
      expect(got.lots.single.id, 'l-new');
    });

    test('isolates ownerUserId — one user\'s snapshot is invisible to '
        'another', () async {
      final store = InMemoryHoldingDailySnapshotStore();
      await store.save(
        LotInventorySnapshot(
          ownerUserId: _user,
          day: DateTime.utc(2026, 1, 31),
          lots: const [],
        ),
      );

      final got = await store.latestOnOrBefore(
        ownerUserId: 'other-user',
        upTo: DateTime.utc(2026, 12, 31),
      );
      expect(got, isNull);
    });
  });
}
