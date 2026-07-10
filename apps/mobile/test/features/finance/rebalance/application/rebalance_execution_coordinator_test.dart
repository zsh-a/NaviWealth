import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_execution_coordinator.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_trade_validation.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_execution_store.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';
import '../data/rebalance_execution_test_fixtures.dart';

void main() {
  test('active empty session is a successful apply and Undo no-op', () async {
    final harness = await _makeHarness(const _EchoTradeService());
    addTearDown(harness.db.close);
    final session = await harness.store.createOrResume(
      ownerUserId: 'owner-a',
      plan: _buyPlan(0),
    );

    final apply = await harness.coordinator.applySession(sessionId: session.id);
    final undo = await harness.coordinator.undoSession(sessionId: session.id);

    expect(apply.isSuccess, isTrue);
    expect(undo.isSuccess, isTrue);
  });

  test('missing session is typed and stopped for apply and Undo', () async {
    final harness = await _makeHarness(const _EchoTradeService());
    addTearDown(harness.db.close);

    final apply = await harness.coordinator.applySession(sessionId: 'missing');
    final undo = await harness.coordinator.undoSession(sessionId: 'missing');

    expect(
      apply.failures.single.code,
      RebalanceExecutionFailureCode.sessionNotFound,
    );
    expect(
      undo.failures.single.code,
      RebalanceExecutionFailureCode.sessionNotFound,
    );
    expect(apply.stopped, isTrue);
    expect(undo.stopped, isTrue);
  });

  test('archived session is typed and stopped for apply and Undo', () async {
    final harness = await _makeHarness(const _EchoTradeService());
    addTearDown(harness.db.close);
    final session = await _readySession(harness.store, itemCount: 1);
    await harness.store.archive(ownerUserId: 'owner-a', sessionId: session.id);

    final apply = await harness.coordinator.applySession(sessionId: session.id);
    final undo = await harness.coordinator.undoSession(sessionId: session.id);

    expect(
      apply.failures.single.code,
      RebalanceExecutionFailureCode.sessionArchived,
    );
    expect(
      undo.failures.single.code,
      RebalanceExecutionFailureCode.sessionArchived,
    );
    expect(apply.stopped, isTrue);
    expect(undo.stopped, isTrue);
  });

  test(
    'apply commits trade rows and execution state in one transaction',
    () async {
      final harness = await _makeHarness(const _EchoTradeService());
      addTearDown(harness.db.close);
      final session = await _readySession(harness.store, itemCount: 1);

      final result = await harness.coordinator.applySession(
        sessionId: session.id,
      );

      expect(
        result.isSuccess,
        isTrue,
        reason: result.failures.map((failure) => failure.cause).join('\n'),
      );
      expect(result.completedItemIds, [session.items.single.id]);
      final id = session.items.single.id;
      expect(
        (await harness.db.select(harness.db.journalEntries).get()).single.id,
        id,
      );
      expect((await harness.db.select(harness.db.prices).get()).single.id, id);
      expect(
        (await harness.store.getItem(ownerUserId: 'owner-a', id: id))?.state,
        RebalanceExecutionItemState.applied,
      );
    },
  );

  test(
    'Stop raised during prepare releases the claim without writes',
    () async {
      final stop = MutableRebalanceStopSignal();
      final harness = await _makeHarness(_StoppingTradeService(stop));
      addTearDown(harness.db.close);
      final session = await _readySession(harness.store, itemCount: 1);

      final result = await harness.coordinator.applySession(
        sessionId: session.id,
        stop: stop,
      );

      expect(result.stopped, isTrue);
      expect(await harness.db.select(harness.db.journalEntries).get(), isEmpty);
      final item = await harness.store.getItem(
        ownerUserId: 'owner-a',
        id: session.items.single.id,
      );
      expect(item?.state, RebalanceExecutionItemState.ready);
      expect(item?.attemptToken, isNull);
    },
  );

  test(
    'Stop raised inside commit completes current item and claims no next',
    () async {
      final stop = MutableRebalanceStopSignal();
      final harness = await _makeHarness(_StopOnFinalBuildTradeService(stop));
      addTearDown(harness.db.close);
      final session = await _readySession(harness.store, itemCount: 2);

      final result = await harness.coordinator.applySession(
        sessionId: session.id,
        stop: stop,
      );

      expect(result.stopped, isTrue);
      expect(result.completedItemIds, [session.items.first.id]);
      expect(
        (await harness.store.getItem(
          ownerUserId: 'owner-a',
          id: session.items.first.id,
        ))?.state,
        RebalanceExecutionItemState.applied,
      );
      final next = await harness.store.getItem(
        ownerUserId: 'owner-a',
        id: session.items[1].id,
      );
      expect(next?.state, RebalanceExecutionItemState.ready);
      expect(next?.attemptToken, isNull);
    },
  );

  test('apply business failure continues to the next reviewed item', () async {
    final harness = await _makeHarness(_FailFirstTradeService());
    addTearDown(harness.db.close);
    final session = await _readySession(harness.store, itemCount: 2);

    final result = await harness.coordinator.applySession(
      sessionId: session.id,
    );

    expect(
      result.completedItemIds,
      [session.items[1].id],
      reason: result.failures.map((failure) => failure.cause).join('\n'),
    );
    expect(
      result.failures.single.code,
      RebalanceExecutionFailureCode.businessFailed,
    );
    expect(
      (await harness.store.getItem(
        ownerUserId: 'owner-a',
        id: session.items[0].id,
      ))?.state,
      RebalanceExecutionItemState.applyFailed,
    );
    expect(
      (await harness.store.getItem(
        ownerUserId: 'owner-a',
        id: session.items[1].id,
      ))?.state,
      RebalanceExecutionItemState.applied,
    );
  });

  test('expired prepare failure with a new token stops as stale', () async {
    var now = testNow;
    final racer = _FailWithCallbackTradeService();
    final harness = await _makeHarness(racer, clock: () => now);
    addTearDown(harness.db.close);
    final session = await _readySession(harness.store, itemCount: 2);
    late RebalanceExecutionAttempt replacement;
    racer.beforeFailure = () async {
      now = now.add(const Duration(minutes: 3));
      replacement = (await harness.store.claimApply(
        ownerUserId: 'owner-a',
        itemId: session.items.first.id,
        leaseDuration: const Duration(minutes: 2),
      ))!;
    };

    final result = await harness.coordinator.applySession(
      sessionId: session.id,
      leaseDuration: const Duration(minutes: 2),
    );

    expect(
      result.failures.single.code,
      RebalanceExecutionFailureCode.staleAttempt,
    );
    expect(result.stopped, isTrue);
    final first = await harness.store.getItem(
      ownerUserId: 'owner-a',
      id: session.items.first.id,
    );
    expect(first?.state, RebalanceExecutionItemState.applying);
    expect(first?.attemptToken, replacement.token);
    final next = await harness.store.getItem(
      ownerUserId: 'owner-a',
      id: session.items[1].id,
    );
    expect(next?.state, RebalanceExecutionItemState.ready);
    expect(next?.attemptToken, isNull);
  });

  test('archive during claim stops before the next item', () async {
    final harness = await _makeHarness(const _EchoTradeService());
    addTearDown(harness.db.close);
    final session = await _readySession(harness.store, itemCount: 2);
    await harness.db.customStatement('''
      CREATE TRIGGER archive_during_apply_claim
      BEFORE UPDATE OF state ON rebalance_execution_items
      WHEN NEW.state = 'applying'
      BEGIN
        UPDATE rebalance_execution_sessions
        SET status = 'archived',
            archived_at_iso = '2026-05-01T00:00:01.000Z',
            updated_at_iso = '2026-05-01T00:00:01.000Z'
        WHERE id = OLD.session_id;
      END
    ''');

    final result = await harness.coordinator.applySession(
      sessionId: session.id,
    );

    expect(result.stopped, isTrue);
    expect(
      result.failures.single.code,
      anyOf(
        RebalanceExecutionFailureCode.sessionArchived,
        RebalanceExecutionFailureCode.staleAttempt,
      ),
    );
    final next = await harness.store.getItem(
      ownerUserId: 'owner-a',
      id: session.items[1].id,
    );
    expect(next?.state, RebalanceExecutionItemState.ready);
    expect(next?.attemptToken, isNull);
  });

  test(
    'execution final SQL failure rolls back all trade and outbox writes',
    () async {
      final harness = await _makeHarness(const _EchoTradeService());
      addTearDown(harness.db.close);
      final session = await _readySession(harness.store, itemCount: 1);
      await harness.db.customStatement('DELETE FROM op_outbox');
      await harness.db.customStatement('''
      CREATE TRIGGER reject_execution_finalize
      BEFORE UPDATE OF state ON rebalance_execution_items
      WHEN NEW.state = 'applied'
      BEGIN SELECT RAISE(ABORT, 'execution finalize failed'); END
    ''');

      final result = await harness.coordinator.applySession(
        sessionId: session.id,
      );

      expect(
        result.failures.single.code,
        RebalanceExecutionFailureCode.businessFailed,
      );
      expect(await harness.db.select(harness.db.journalEntries).get(), isEmpty);
      expect(await harness.db.select(harness.db.postings).get(), isEmpty);
      expect(await harness.db.select(harness.db.prices).get(), isEmpty);
      expect(await harness.outbox.depth(), 0);
      expect(
        (await harness.store.getItem(
          ownerUserId: 'owner-a',
          id: session.items.single.id,
        ))?.state,
        RebalanceExecutionItemState.applyFailed,
      );
    },
  );

  test('fresh deleted asset fails validation before ledger writes', () async {
    final harness = await _makeHarness(const _EchoTradeService());
    addTearDown(harness.db.close);
    final session = await _readySession(harness.store, itemCount: 1);
    await (harness.db.update(harness.db.assets)
          ..where((row) => row.id.equals('us_stock:AAPL')))
        .write(AssetsCompanion(deletedAt: Value(testNow)));
    await harness.db.customStatement('DELETE FROM op_outbox');

    final result = await harness.coordinator.applySession(
      sessionId: session.id,
    );

    expect(
      result.failures.single.code,
      RebalanceExecutionFailureCode.validationFailed,
    );
    expect(await harness.db.select(harness.db.journalEntries).get(), isEmpty);
    expect(await harness.db.select(harness.db.prices).get(), isEmpty);
    expect(await harness.outbox.depth(), 0);
  });

  test('Undo final SQL failure rolls back every trade tombstone', () async {
    final harness = await _makeHarness(const _EchoTradeService());
    addTearDown(harness.db.close);
    final session = await _readySession(harness.store, itemCount: 1);
    final applied = await harness.coordinator.applySession(
      sessionId: session.id,
    );
    expect(applied.isSuccess, isTrue);
    await harness.db.customStatement('DELETE FROM op_outbox');
    await harness.db.customStatement('''
      CREATE TRIGGER reject_execution_undo_finalize
      BEFORE UPDATE OF state ON rebalance_execution_items
      WHEN NEW.state = 'undone'
      BEGIN SELECT RAISE(ABORT, 'execution undo finalize failed'); END
    ''');

    final result = await harness.coordinator.undoSession(sessionId: session.id);

    expect(
      result.failures.single.code,
      RebalanceExecutionFailureCode.businessFailed,
    );
    expect(
      (await harness.db.select(harness.db.journalEntries).getSingle())
          .deletedAt,
      isNull,
    );
    expect(
      (await harness.db.select(harness.db.postings).get()).every(
        (posting) => posting.deletedAt == null,
      ),
      isTrue,
    );
    expect(
      (await harness.db.select(harness.db.prices).getSingle()).deletedAt,
      isNull,
    );
    expect(await harness.outbox.depth(), 0);
    expect(
      (await harness.store.getItem(
        ownerUserId: 'owner-a',
        id: session.items.single.id,
      ))?.state,
      RebalanceExecutionItemState.undoFailed,
    );
  });

  test('Undo failure on highest sequence stops before lower item', () async {
    final harness = await _makeHarness(const _EchoTradeService());
    addTearDown(harness.db.close);
    final session = await _readySession(harness.store, itemCount: 2);
    final applied = await harness.coordinator.applySession(
      sessionId: session.id,
    );
    expect(
      applied.completedItemIds,
      hasLength(2),
      reason: applied.failures.map((failure) => failure.cause).join('\n'),
    );
    final reverse = await harness.store.listAppliedForUndo(
      ownerUserId: 'owner-a',
      sessionId: session.id,
    );
    final higher = reverse.first;
    final lower = reverse.last;
    await (harness.db.update(harness.db.journalEntries)
          ..where((row) => row.id.equals(higher.id)))
        .write(const JournalEntriesCompanion(narration: Value('later edit')));

    final result = await harness.coordinator.undoSession(sessionId: session.id);

    expect(result.completedItemIds, isEmpty);
    expect(result.stopped, isTrue);
    expect(result.failures.single.itemId, higher.id);
    expect(
      (await harness.store.getItem(
        ownerUserId: 'owner-a',
        id: higher.id,
      ))?.state,
      RebalanceExecutionItemState.undoFailed,
    );
    expect(
      (await harness.store.getItem(
        ownerUserId: 'owner-a',
        id: lower.id,
      ))?.state,
      RebalanceExecutionItemState.applied,
    );
  });

  test('Undo failure whose lease expires while marking is stale', () async {
    final clock = _SteppingClock(testNow);
    final harness = await _makeHarness(
      const _EchoTradeService(),
      clock: clock.call,
    );
    addTearDown(harness.db.close);
    final session = await _readySession(harness.store, itemCount: 2);
    final applied = await harness.coordinator.applySession(
      sessionId: session.id,
    );
    expect(applied.isSuccess, isTrue);
    final reverse = await harness.store.listAppliedForUndo(
      ownerUserId: 'owner-a',
      sessionId: session.id,
    );
    await (harness.db.update(harness.db.journalEntries)
          ..where((row) => row.id.equals(reverse.first.id)))
        .write(const JournalEntriesCompanion(narration: Value('later edit')));
    clock.step = const Duration(minutes: 1);

    final result = await harness.coordinator.undoSession(
      sessionId: session.id,
      leaseDuration: const Duration(minutes: 2),
    );

    expect(
      result.failures.single.code,
      RebalanceExecutionFailureCode.staleAttempt,
    );
    expect(result.stopped, isTrue);
    expect(
      (await harness.store.getItem(
        ownerUserId: 'owner-a',
        id: reverse.last.id,
      ))?.state,
      RebalanceExecutionItemState.applied,
    );
  });
}

Future<
  ({
    AppDatabase db,
    DriftOutboxStore outbox,
    RebalanceExecutionStore store,
    RebalanceExecutionCoordinator coordinator,
  })
>
_makeHarness(
  TradeEntryService tradeService, {
  RebalanceExecutionClock? clock,
}) async {
  final db = makeTestDatabase();
  final outbox = DriftOutboxStore(db);
  final stamper = makeStubStamper(userId: 'owner-a');
  final securities = SecuritiesAssetRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
  );
  final journal = JournalEntryRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
    fxRateSource: const IdentityFxRateSource(),
    baseCurrency: 'USD',
  );
  final prices = PriceRepository(db: db, outbox: outbox, stamper: stamper);
  for (final (id, type) in const [
    ('broker-account', AccountCategory.broker),
    ('cash-account', AccountCategory.cash),
  ]) {
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: id,
            type: type,
            name: id,
            currency: 'USD',
            category: const Value(AccountSide.asset),
            ownerUserId: 'owner-a',
            updatedAt: testNow,
            updatedByDevice: 'device-a',
            hlc: Hlc(
              wallMillis: testNow.millisecondsSinceEpoch,
              counter: 0,
              nodeId: 'device-a',
            ),
          ),
        );
  }
  await securities.upsertSecurity(
    symbol: 'AAPL',
    market: AssetMarket.usStock,
    type: AssetType.stock,
    currency: 'USD',
    name: 'Apple',
  );
  final submission = TradeEntrySubmissionService(
    db: db,
    securitiesRepo: securities,
    tradeService: tradeService,
    journalEntryRepo: journal,
    priceRepo: prices,
    currentUserId: () async => 'owner-a',
  );
  final store = RebalanceExecutionStore(db, clock: clock ?? () => testNow);
  return (
    db: db,
    outbox: outbox,
    store: store,
    coordinator: RebalanceExecutionCoordinator(
      db: db,
      store: store,
      validation: RebalanceTradeValidation(db),
      tradeSubmission: submission,
      currentUserId: () async => 'owner-a',
    ),
  );
}

Future<RebalanceExecutionSession> _readySession(
  RebalanceExecutionStore store, {
  required int itemCount,
}) async {
  final plan = _buyPlan(itemCount);
  var session = await store.createOrResume(ownerUserId: 'owner-a', plan: plan);
  for (final item in session.items) {
    await store.saveRequest(
      ownerUserId: 'owner-a',
      itemId: item.id,
      request: testRequest(item.id),
    );
  }
  session = (await store.getSession(ownerUserId: 'owner-a', id: session.id))!;
  return session;
}

RebalancePlan _buyPlan(int count) {
  final base = testPlan(reverseCollections: true);
  final buy = base.trades.first;
  return RebalancePlan(
    target: base.target,
    actualWeights: base.actualWeights,
    drifts: base.drifts,
    trades: List<SuggestedTrade>.filled(count, buy),
    estimatedFees: base.estimatedFees,
    estimatedTaxes: base.estimatedTaxes,
    driftBeforePct: base.driftBeforePct,
    driftAfterPct: base.driftAfterPct,
    totalAssets: base.totalAssets,
  );
}

class _EchoTradeService implements TradeEntryService {
  const _EchoTradeService();

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    final price = draft.price ?? Decimal.one;
    return TradeEntryPlan(
      trade: PlannedTrade(
        id: draft.transactionId!,
        accountId: draft.accountId,
        assetId: draft.asset.id,
        type: draft.type,
        quantity: draft.quantity,
        price: price,
        currency: draft.currency,
        tradeDate: draft.tradeDate,
        fee: draft.fee,
        tax: draft.tax,
        note: draft.note,
      ),
      createdLot: draft.type == TradeType.buy
          ? Lot(
              id: '${draft.transactionId}-lot',
              openingTransactionId: draft.transactionId!,
              accountId: draft.accountId,
              assetId: draft.asset.id,
              currency: draft.currency,
              originalQuantity: draft.quantity,
              remainingQuantity: draft.quantity,
              costPerUnit:
                  ((draft.quantity * price + draft.feeOrZero) / draft.quantity)
                      .toDecimal(scaleOnInfinitePrecision: 16),
              openedAt: draft.tradeDate,
            )
          : null,
      pricing: PriceProvenance.userSupplied,
    );
  }
}

final class _StoppingTradeService extends _EchoTradeService {
  _StoppingTradeService(this.stop);

  final MutableRebalanceStopSignal stop;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    stop.stop();
    return super.buildPlan(draft, openLots: openLots);
  }
}

final class _StopOnFinalBuildTradeService extends _EchoTradeService {
  _StopOnFinalBuildTradeService(this.stop);

  final MutableRebalanceStopSignal stop;
  var calls = 0;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    calls += 1;
    if (calls == 2) stop.stop();
    return super.buildPlan(draft, openLots: openLots);
  }
}

final class _FailFirstTradeService extends _EchoTradeService {
  var calls = 0;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    calls += 1;
    if (calls == 1) throw StateError('injected prepare failure');
    return super.buildPlan(draft, openLots: openLots);
  }
}

final class _FailWithCallbackTradeService extends _EchoTradeService {
  Future<void> Function()? beforeFailure;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    await beforeFailure?.call();
    throw StateError('injected preparation failure');
  }
}

final class _SteppingClock {
  _SteppingClock(this.now);

  DateTime now;
  Duration step = Duration.zero;

  DateTime call() {
    final value = now;
    now = now.add(step);
    return value;
  }
}
