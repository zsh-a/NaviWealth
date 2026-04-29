import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/domain/transaction.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/investment/domain/holding_price_source.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/investment/domain/returns/returns_service.dart';
import 'package:naviwealth/features/investment/domain/returns/xirr_engine.dart';

const _user = 'user-1';

Decimal _d(String s) => Decimal.parse(s);

Matcher _closeToD(double v, [double eps = 1e-4]) =>
    inInclusiveRange(v - eps, v + eps);

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
    ),
  );
}

Lot _lot({
  required String assetId,
  required String accountId,
  required Decimal qty,
  required Decimal cost,
  required String currency,
  String id = 'lot',
  DateTime? openedAt,
}) {
  return Lot(
    id: id,
    openingTransactionId: 'tx-$id',
    accountId: accountId,
    assetId: assetId,
    currency: currency,
    originalQuantity: qty,
    remainingQuantity: qty,
    costPerUnit: cost,
    openedAt: openedAt ?? DateTime.utc(2025, 1, 1),
  );
}

class _FixedTxRepo implements ReturnsTransactionsRepository {
  _FixedTxRepo(this.txs);
  final List<Transaction> txs;

  @override
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async {
    return txs
        .where(
          (t) =>
              t.sync.ownerUserId == ownerUserId &&
              t.sync.deletedAt == null &&
              !t.tradeDate.isBefore(from) &&
              !t.tradeDate.isAfter(to),
        )
        .toList();
  }
}

/// Lots-by-date source. Each entry maps an `asOf` (UTC instant) to the lot
/// inventory at that moment. Lookups pick the latest `asOf` ≤ requested.
class _FixedLotsSource implements ReturnsLotsSource {
  _FixedLotsSource(this.byAsOf);
  final Map<DateTime, List<Lot>> byAsOf;

  @override
  Future<List<Lot>> lotsAt({
    required String ownerUserId,
    required DateTime asOf,
  }) async {
    DateTime? best;
    for (final k in byAsOf.keys) {
      if (k.isAfter(asOf)) continue;
      if (best == null || k.isAfter(best)) best = k;
    }
    return best == null ? const [] : byAsOf[best]!;
  }
}

ReturnsService _service({
  required List<Transaction> txs,
  required Map<DateTime, List<Lot>> lotsByAsOf,
  required HoldingPriceSource prices,
  Iterable<FxRate> rates = const [],
  String base = 'USD',
}) {
  return ReturnsService(
    ownerUserId: _user,
    baseCurrency: base,
    transactions: _FixedTxRepo(txs),
    lots: _FixedLotsSource(lotsByAsOf),
    prices: prices,
    converter: FxRateCurrencyConverter(InMemoryFxRateLookup(rates)),
  );
}

void main() {
  group('ReturnsService — single asset XIRR', () {
    test('buy + hold + terminal mark: rate equals (1 + market_return) − 1 over '
        'one year, regardless of fees', () async {
      // Window opens Jan 1 2025; buy at noon Jan 1 (inside window since
      // strictly after `from`), terminal at noon Jan 1 2026 — exactly one
      // year between the two flows so XIRR = 1200/1005 − 1.
      final svc = _service(
        txs: [
          _tx(
            id: 'buy',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('10'),
            price: _d('100'),
            currency: 'USD',
            fee: _d('5'),
            tradeDate: DateTime.utc(2025, 1, 1, 12),
          ),
        ],
        lotsByAsOf: {
          DateTime.utc(2025, 1, 1): const [],
          DateTime.utc(2026, 1, 1, 12): [
            _lot(
              assetId: 'AAPL',
              accountId: 'a',
              qty: _d('10'),
              cost: _d('100'),
              currency: 'USD',
            ),
          ],
        },
        prices: InMemoryHoldingPriceSource([
          HoldingPriceObservation(
            assetId: 'AAPL',
            price: _d('120'),
            currency: 'USD',
            asOf: DateTime.utc(2026, 1, 1, 12),
          ),
        ]),
      );

      final report = await svc.assetXirr(
        assetId: 'AAPL',
        from: DateTime.utc(2025, 1, 1),
        to: DateTime.utc(2026, 1, 1, 12),
      );
      expect(report.solution, isA<XirrConverged>());
      expect(
        (report.solution as XirrConverged).rate,
        _closeToD(1200 / 1005 - 1, 1e-4),
      );
      expect(report.initialValueInBase, Decimal.zero);
      expect(report.terminalValueInBase, _d('1200'));
    });

    test('mid-window dividend lifts XIRR above pure capital gain', () async {
      final svc = _service(
        txs: [
          _tx(
            id: 'buy',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('10'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2025, 1, 2),
          ),
          _tx(
            id: 'div',
            type: TransactionType.dividend,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('10'),
            price: _d('5'), // $5/share total $50 dividend mid-year
            currency: 'USD',
            tradeDate: DateTime.utc(2025, 7, 1),
          ),
        ],
        lotsByAsOf: {
          DateTime.utc(2025, 1, 1): const [],
          DateTime.utc(2026, 1, 1): [
            _lot(
              assetId: 'AAPL',
              accountId: 'a',
              qty: _d('10'),
              cost: _d('100'),
              currency: 'USD',
            ),
          ],
        },
        prices: InMemoryHoldingPriceSource([
          HoldingPriceObservation(
            assetId: 'AAPL',
            price: _d('110'),
            currency: 'USD',
            asOf: DateTime.utc(2026, 1, 1),
          ),
        ]),
      );

      final withDiv = await svc.assetXirr(
        assetId: 'AAPL',
        from: DateTime.utc(2025, 1, 1),
        to: DateTime.utc(2026, 1, 1),
      );
      // XIRR should be > pure capital gain rate of 10%.
      expect(withDiv.solution, isA<XirrConverged>());
      expect((withDiv.solution as XirrConverged).rate, greaterThan(0.10));
    });

    test('initial bookend captures already-held position; in-window flows '
        'start strictly after `from`', () async {
      // 20 AAPL already held at Jan 1 (cost $100, market $110), nothing
      // happens in the window, terminal price $121. XIRR = 10% per year.
      final svc = _service(
        txs: const [],
        lotsByAsOf: {
          DateTime.utc(2025, 1, 1): [
            _lot(
              assetId: 'AAPL',
              accountId: 'a',
              qty: _d('20'),
              cost: _d('100'),
              currency: 'USD',
            ),
          ],
          DateTime.utc(2026, 1, 1): [
            _lot(
              assetId: 'AAPL',
              accountId: 'a',
              qty: _d('20'),
              cost: _d('100'),
              currency: 'USD',
            ),
          ],
        },
        prices: InMemoryHoldingPriceSource([
          HoldingPriceObservation(
            assetId: 'AAPL',
            price: _d('110'),
            currency: 'USD',
            asOf: DateTime.utc(2025, 1, 1),
          ),
          HoldingPriceObservation(
            assetId: 'AAPL',
            price: _d('121'),
            currency: 'USD',
            asOf: DateTime.utc(2026, 1, 1),
          ),
        ]),
      );

      final report = await svc.assetXirr(
        assetId: 'AAPL',
        from: DateTime.utc(2025, 1, 1),
        to: DateTime.utc(2026, 1, 1),
      );
      // Initial $2200 → terminal $2420 over 1y = 10% XIRR.
      expect(report.solution, isA<XirrConverged>());
      expect((report.solution as XirrConverged).rate, _closeToD(0.10, 1e-4));
      expect(report.initialValueInBase, _d('2200'));
      expect(report.terminalValueInBase, _d('2420'));
    });
  });

  group('ReturnsService — portfolio XIRR (account scope)', () {
    test('deposits + terminal portfolio value give the IRR; '
        'internal trades do not appear as flows', () async {
      // Two deposits ($1000 each, six months apart), one buy that consumes
      // the deposited cash, and a terminal portfolio value of $2300.
      final svc = _service(
        txs: [
          _tx(
            id: 'd1',
            type: TransactionType.deposit,
            accountId: 'a',
            assetId: null,
            quantity: _d('1'),
            price: _d('1000'),
            currency: 'USD',
            tradeDate: DateTime.utc(2025, 1, 2),
          ),
          _tx(
            id: 'd2',
            type: TransactionType.deposit,
            accountId: 'a',
            assetId: null,
            quantity: _d('1'),
            price: _d('1000'),
            currency: 'USD',
            tradeDate: DateTime.utc(2025, 7, 2),
          ),
          _tx(
            // Internal trade, must not enter the portfolio-XIRR flow set.
            id: 'buy',
            type: TransactionType.buy,
            accountId: 'a',
            assetId: 'AAPL',
            quantity: _d('20'),
            price: _d('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2025, 7, 3),
          ),
        ],
        lotsByAsOf: {
          DateTime.utc(2025, 1, 1): const [],
          DateTime.utc(2026, 1, 1): [
            _lot(
              assetId: 'AAPL',
              accountId: 'a',
              qty: _d('20'),
              cost: _d('100'),
              currency: 'USD',
            ),
          ],
        },
        prices: InMemoryHoldingPriceSource([
          HoldingPriceObservation(
            assetId: 'AAPL',
            price: _d('115'),
            currency: 'USD',
            asOf: DateTime.utc(2026, 1, 1),
          ),
        ]),
      );

      final report = await svc.portfolioXirr(
        from: DateTime.utc(2025, 1, 1),
        to: DateTime.utc(2026, 1, 1),
      );
      expect(report.solution, isA<XirrConverged>());
      // Flow ledger: −1000 (Jan 2), −1000 (Jul 2), +2300 (Jan 1 2026). The
      // buy is absent (internal). Initial bookend is zero (no position).
      final amounts = report.flows.map((f) => f.amount).toList()..sort();
      expect(amounts, [-1000.0, -1000.0, 2300.0]);
      expect(report.initialValueInBase, Decimal.zero);
      expect(report.terminalValueInBase, _d('2300'));
    });
  });

  group('ReturnsService — multi-dimension', () {
    test('byAccountXirr returns one report per requested account, '
        'isolated by accountId', () async {
      final svc = _service(
        txs: [
          _tx(
            id: 'd-a',
            type: TransactionType.deposit,
            accountId: 'A',
            assetId: null,
            quantity: _d('1'),
            price: _d('1000'),
            currency: 'USD',
            tradeDate: DateTime.utc(2025, 1, 2),
          ),
          _tx(
            id: 'd-b',
            type: TransactionType.deposit,
            accountId: 'B',
            assetId: null,
            quantity: _d('1'),
            price: _d('500'),
            currency: 'USD',
            tradeDate: DateTime.utc(2025, 1, 2),
          ),
        ],
        lotsByAsOf: {
          DateTime.utc(2025, 1, 1): const [],
          DateTime.utc(2026, 1, 1): [
            _lot(
              id: 'la',
              assetId: 'AAPL',
              accountId: 'A',
              qty: _d('10'),
              cost: _d('100'),
              currency: 'USD',
            ),
            _lot(
              id: 'lb',
              assetId: 'TSLA',
              accountId: 'B',
              qty: _d('5'),
              cost: _d('100'),
              currency: 'USD',
            ),
          ],
        },
        prices: InMemoryHoldingPriceSource([
          HoldingPriceObservation(
            assetId: 'AAPL',
            price: _d('120'),
            currency: 'USD',
            asOf: DateTime.utc(2026, 1, 1),
          ),
          HoldingPriceObservation(
            assetId: 'TSLA',
            price: _d('120'),
            currency: 'USD',
            asOf: DateTime.utc(2026, 1, 1),
          ),
        ]),
      );

      final reports = await svc.byAccountXirr(
        accountIds: ['A', 'B'],
        from: DateTime.utc(2025, 1, 1),
        to: DateTime.utc(2026, 1, 1),
      );
      expect(reports.keys, containsAll(['A', 'B']));

      // Account A: −1000 (deposit) + 1200 (terminal AAPL value) → 20%.
      final a = reports['A']!;
      expect(a.solution, isA<XirrConverged>());
      expect((a.solution as XirrConverged).rate, _closeToD(0.20, 1e-3));

      // Account B: −500 (deposit) + 600 (terminal TSLA value) → 20%.
      final b = reports['B']!;
      expect(b.solution, isA<XirrConverged>());
      expect((b.solution as XirrConverged).rate, _closeToD(0.20, 1e-3));
    });

    test(
      'byBucketXirr aggregates positions across multiple assetIds per bucket',
      () async {
        final svc = _service(
          txs: [
            _tx(
              id: 'b1',
              type: TransactionType.buy,
              accountId: 'a',
              assetId: 'AAPL',
              quantity: _d('10'),
              price: _d('100'),
              currency: 'USD',
              tradeDate: DateTime.utc(2025, 1, 2),
            ),
            _tx(
              id: 'b2',
              type: TransactionType.buy,
              accountId: 'a',
              assetId: 'MSFT',
              quantity: _d('10'),
              price: _d('100'),
              currency: 'USD',
              tradeDate: DateTime.utc(2025, 1, 2),
            ),
            _tx(
              id: 'b3',
              type: TransactionType.buy,
              accountId: 'a',
              assetId: 'JPM',
              quantity: _d('10'),
              price: _d('100'),
              currency: 'USD',
              tradeDate: DateTime.utc(2025, 1, 2),
            ),
          ],
          lotsByAsOf: {
            DateTime.utc(2025, 1, 1): const [],
            DateTime.utc(2026, 1, 1): [
              _lot(
                id: 'a',
                assetId: 'AAPL',
                accountId: 'a',
                qty: _d('10'),
                cost: _d('100'),
                currency: 'USD',
              ),
              _lot(
                id: 'm',
                assetId: 'MSFT',
                accountId: 'a',
                qty: _d('10'),
                cost: _d('100'),
                currency: 'USD',
              ),
              _lot(
                id: 'j',
                assetId: 'JPM',
                accountId: 'a',
                qty: _d('10'),
                cost: _d('100'),
                currency: 'USD',
              ),
            ],
          },
          prices: InMemoryHoldingPriceSource([
            HoldingPriceObservation(
              assetId: 'AAPL',
              price: _d('120'),
              currency: 'USD',
              asOf: DateTime.utc(2026, 1, 1),
            ),
            HoldingPriceObservation(
              assetId: 'MSFT',
              price: _d('120'),
              currency: 'USD',
              asOf: DateTime.utc(2026, 1, 1),
            ),
            HoldingPriceObservation(
              assetId: 'JPM',
              price: _d('110'),
              currency: 'USD',
              asOf: DateTime.utc(2026, 1, 1),
            ),
          ]),
        );

        final reports = await svc.byBucketXirr(
          bucketing: const XirrBucketing({
            'tech': {'AAPL', 'MSFT'},
            'finance': {'JPM'},
          }),
          from: DateTime.utc(2025, 1, 1),
          to: DateTime.utc(2026, 1, 1),
        );

        // tech bucket: −2000 (two buys) + 2400 (terminal of AAPL+MSFT) → 20%.
        final tech = reports['tech']!;
        expect(tech.solution, isA<XirrConverged>());
        expect((tech.solution as XirrConverged).rate, _closeToD(0.20, 1e-3));

        // finance bucket: −1000 + 1100 → 10%.
        final fin = reports['finance']!;
        expect(fin.solution, isA<XirrConverged>());
        expect((fin.solution as XirrConverged).rate, _closeToD(0.10, 1e-3));
      },
    );
  });

  group('ReturnsService — multi-currency unification', () {
    test(
      'CNY position values into a USD base portfolio at trade-date FX',
      () async {
        // Buy 100 CNY at 1000 CNY/share = 100,000 CNY, 1 CNY = 0.14 USD →
        // 14,000 USD outflow. Terminal price 1100 CNY * 100 = 110,000 CNY at
        // 1 CNY = 0.15 USD → 16,500 USD. XIRR = 16,500/14,000 − 1 ≈ 17.86%.
        final svc = _service(
          txs: [
            _tx(
              id: 'b',
              type: TransactionType.buy,
              accountId: 'a',
              assetId: '600519',
              quantity: _d('100'),
              price: _d('1000'),
              currency: 'CNY',
              tradeDate: DateTime.utc(2025, 1, 2),
            ),
          ],
          lotsByAsOf: {
            DateTime.utc(2025, 1, 1): const [],
            DateTime.utc(2026, 1, 1): [
              _lot(
                assetId: '600519',
                accountId: 'a',
                qty: _d('100'),
                cost: _d('1000'),
                currency: 'CNY',
              ),
            ],
          },
          prices: InMemoryHoldingPriceSource([
            HoldingPriceObservation(
              assetId: '600519',
              price: _d('1100'),
              currency: 'CNY',
              asOf: DateTime.utc(2026, 1, 1),
            ),
          ]),
          rates: [
            FxRate(
              base: 'CNY',
              quote: 'USD',
              date: DateTime.utc(2025, 1, 2),
              rate: _d('0.14'),
              source: 'fixture',
            ),
            FxRate(
              base: 'CNY',
              quote: 'USD',
              date: DateTime.utc(2026, 1, 1),
              rate: _d('0.15'),
              source: 'fixture',
            ),
          ],
        );

        final report = await svc.assetXirr(
          assetId: '600519',
          from: DateTime.utc(2025, 1, 1),
          to: DateTime.utc(2026, 1, 1),
        );
        expect(report.solution, isA<XirrConverged>());
        expect(
          (report.solution as XirrConverged).rate,
          _closeToD(16500 / 14000 - 1, 1e-3),
        );
      },
    );
  });

  group('ReturnsService — input validation', () {
    test('rejects window where to <= from with ArgumentError', () async {
      final svc = _service(
        txs: const [],
        lotsByAsOf: const {},
        prices: InMemoryHoldingPriceSource(const []),
      );
      await expectLater(
        svc.portfolioXirr(
          from: DateTime.utc(2026, 1, 1),
          to: DateTime.utc(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('ReturnsService — fallback to absolute return', () {
    test('window with no flows and no position → fallback', () async {
      final svc = _service(
        txs: const [],
        lotsByAsOf: {
          DateTime.utc(2025, 1, 1): const [],
          DateTime.utc(2026, 1, 1): const [],
        },
        prices: InMemoryHoldingPriceSource(const []),
      );

      final report = await svc.portfolioXirr(
        from: DateTime.utc(2025, 1, 1),
        to: DateTime.utc(2026, 1, 1),
      );
      expect(report.solution, isA<XirrFallbackAbsolute>());
    });
  });
}
