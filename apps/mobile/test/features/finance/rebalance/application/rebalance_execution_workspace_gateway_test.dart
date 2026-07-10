import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_execution_coordinator.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_execution_workspace_gateway.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_trade_validation.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_execution_store.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';
import '../data/rebalance_execution_test_fixtures.dart';

void main() {
  test('resolves the authenticated owner again for every read', () async {
    final harness = await _makeHarness();
    addTearDown(harness.db.close);
    final session = await harness.store.createOrResume(
      ownerUserId: 'owner-a',
      plan: testPlan(),
    );

    expect((await harness.gateway.active())?.id, session.id);
    harness.owner = 'owner-b';
    expect(await harness.gateway.active(), isNull);
    expect(await harness.gateway.session(session.id), isNull);
    harness.owner = 'owner-a';
    expect((await harness.gateway.session(session.id))?.id, session.id);
  });

  test('wrong owner cannot spoof any session or item mutation', () async {
    final harness = await _makeHarness();
    addTearDown(harness.db.close);
    final session = await harness.store.createOrResume(
      ownerUserId: 'owner-a',
      plan: testPlan(reverseCollections: true),
    );
    final item = session.items.first;
    harness.owner = 'owner-b';

    Future<void> expectHidden(Future<Object?> future) =>
        expectLater(future, throwsA(isA<RebalanceExecutionNotFound>()));

    await expectHidden(harness.gateway.skip(item.id));
    await expectHidden(harness.gateway.reopen(item.id));
    await expectHidden(harness.gateway.archive(session.id));
    await expectHidden(harness.gateway.apply(session.id));
    await expectHidden(harness.gateway.undo(session.id));
    await expectHidden(
      harness.gateway.replaceActive(
        expectedSessionId: session.id,
        expectedFingerprint: session.planFingerprint,
        plan: testPlan(buyAmount: Decimal.fromInt(101)),
      ),
    );
    await expectHidden(
      harness.gateway.saveReviewedRequest(
        expected: item,
        request: testRequest(item.id, owner: 'owner-b'),
      ),
    );

    expect((await harness.store.getActive('owner-a'))?.id, session.id);
  });

  test('second editor cannot overwrite a request saved by the first', () async {
    final harness = await _makeHarness();
    addTearDown(harness.db.close);
    final session = await harness.store.createOrResume(
      ownerUserId: 'owner-a',
      plan: testPlan(reverseCollections: true),
    );
    final opened = session.items.firstWhere((item) => item.suggestion.isBuy);
    final firstRequest = testRequest(opened.id);
    await _seedReviewedReferences(harness.db, firstRequest);

    final firstSaved = await harness.gateway.saveReviewedRequest(
      expected: opened,
      request: firstRequest,
    );
    await expectLater(
      harness.gateway.saveReviewedRequest(
        expected: opened,
        request: RebalanceExecutionRequest(
          transactionId: firstRequest.transactionId,
          account: firstRequest.account,
          cashAccount: firstRequest.cashAccount,
          asset: firstRequest.asset,
          type: firstRequest.type,
          quantity: Decimal.fromInt(2),
          price: firstRequest.price,
          currency: firstRequest.currency,
          tradeDate: firstRequest.tradeDate,
          fee: firstRequest.fee,
          tax: firstRequest.tax,
          note: 'stale second editor',
        ),
      ),
      throwsA(isA<RebalanceExecutionConflict>()),
    );

    final persisted = await harness.gateway.session(session.id);
    expect(
      persisted!.items.firstWhere((item) => item.id == opened.id).request,
      firstSaved.request,
    );
  });
}

final class _Harness {
  _Harness({required this.db, required this.store, required this.gateway});

  final AppDatabase db;
  final RebalanceExecutionStore store;
  final RebalanceExecutionWorkspaceGateway gateway;
  String owner = 'owner-a';
}

Future<_Harness> _makeHarness() async {
  final db = makeTestDatabase();
  final outbox = DriftOutboxStore(db);
  final stamper = makeStubStamper(userId: 'owner-a');
  final store = RebalanceExecutionStore(db, clock: () => testNow);
  final validation = RebalanceTradeValidation(db);
  late final _Harness harness;
  Future<String> currentOwner() async => harness.owner;
  final submission = TradeEntrySubmissionService(
    db: db,
    securitiesRepo: SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    ),
    tradeService: const _UnusedTradeEntryService(),
    journalEntryRepo: JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'USD',
    ),
    priceRepo: PriceRepository(db: db, outbox: outbox, stamper: stamper),
    currentUserId: currentOwner,
  );
  final coordinator = RebalanceExecutionCoordinator(
    db: db,
    store: store,
    validation: validation,
    tradeSubmission: submission,
    currentUserId: currentOwner,
  );
  harness = _Harness(
    db: db,
    store: store,
    gateway: DefaultRebalanceExecutionWorkspaceGateway(
      db: db,
      store: store,
      validation: validation,
      coordinator: coordinator,
      currentUserId: currentOwner,
    ),
  );
  return harness;
}

final class _UnusedTradeEntryService implements TradeEntryService {
  const _UnusedTradeEntryService();

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) => throw UnimplementedError();
}

Future<void> _seedReviewedReferences(
  AppDatabase db,
  RebalanceExecutionRequest request,
) async {
  for (final account in [request.account, request.cashAccount!]) {
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: account.id,
            type: account.type,
            name: account.name,
            currency: account.currency,
            institution: Value(account.institution),
            accountNumber: Value(account.accountNumber),
            note: Value(account.note),
            archived: Value(account.archived),
            category: Value(account.category),
            parentId: Value(account.parentId),
            icon: Value(account.icon),
            color: Value(account.color),
            ownerUserId: account.sync.ownerUserId,
            updatedAt: account.sync.updatedAt,
            updatedByDevice: account.sync.updatedByDevice,
            hlc: account.sync.hlc,
          ),
        );
  }
  final asset = request.asset;
  await db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: asset.id,
          type: asset.type,
          symbol: asset.symbol,
          currency: asset.currency,
          name: Value(asset.name),
          market: Value(asset.market),
          industry: Value(asset.industry),
          region: Value(asset.region),
          isin: Value(asset.isin),
          logoUrl: Value(asset.logoUrl),
          metadataJson: Value(asset.metadataJson),
          ownerUserId: asset.sync.ownerUserId,
          updatedAt: asset.sync.updatedAt,
          updatedByDevice: asset.sync.updatedByDevice,
          hlc: asset.sync.hlc,
        ),
      );
}
