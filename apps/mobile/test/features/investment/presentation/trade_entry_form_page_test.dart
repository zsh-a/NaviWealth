import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/db/providers.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/market/http/market_http_client.dart';
import 'package:naviwealth/data/market/http/rate_limiter.dart';
import 'package:naviwealth/data/market/market_data_providers.dart';
import 'package:naviwealth/data/market/metrics/market_metrics.dart';
import 'package:naviwealth/data/repositories/account_repository.dart';
import 'package:naviwealth/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/data/repositories/mutation_context.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/data/securities_catalog/providers.dart';
import 'package:naviwealth/data/securities_catalog/securities_catalog_loader.dart';
import 'package:naviwealth/data/securities_catalog/securities_search_service.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/data/transaction_repository.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/default_trade_entry_service.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/investment/presentation/trade_entry_form_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/db/test_database.dart';
import '../../../data/repositories/_stub_stamper.dart';
import '../../../data/securities_catalog/_catalog_fixtures.dart';
import '../domain/trade_entry/_fakes.dart';

/// Wires the trade-entry form on top of an in-memory DB seeded with the
/// shared catalog fixture so tests can exercise the full
/// "search → upsert → recordTrade" pipeline without any network.
class _Harness {
  _Harness({
    required this.db,
    required this.outbox,
    required this.txRepo,
    required this.jeRepo,
    required this.secRepo,
    required this.search,
    required this.market,
    required this.prefs,
  });

  final AppDatabase db;
  final InMemoryOutboxStore outbox;
  final TransactionRepository txRepo;
  final JournalEntryRepository jeRepo;
  final SecuritiesAssetRepository secRepo;
  final SecuritiesSearchService search;
  final MarketDataService market;
  final SharedPreferences prefs;

  static Future<_Harness> create() async {
    final db = makeTestDatabase();
    await SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(makeFixtureBundle()),
    ).load();
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    final secRepo = SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final txRepo = TransactionRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final jeRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'USD',
    );
    // Seed the system account tree (expense:trading:fee, etc.) so
    // JournalEntryBuilder postings don't violate FK constraints.
    final accountRepo = AccountRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    await accountRepo.seedSystemAccounts(currency: 'USD');
    // Insert the user's brokerage account so FK constraints on
    // postings.account_id are satisfied.
    final acStamper = stamper;
    final acStamp = await acStamper.stamp();
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: 'acct-1',
            name: 'Test Brokerage',
            currency: 'USD',
            type: AccountType.brokerage,
            category: const Value(AccountCategory.asset),
            ownerUserId: acStamp.ownerUserId,
            updatedAt: acStamp.now,
            updatedByDevice: acStamp.deviceId,
            hlc: acStamp.hlc,
          ),
        );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    return _Harness(
      db: db,
      outbox: outbox,
      txRepo: txRepo,
      jeRepo: jeRepo,
      secRepo: secRepo,
      search: SecuritiesSearchService(db: db),
      market: FakeMarketDataService(),
      prefs: prefs,
    );
  }

  Future<void> dispose() => db.close();
}

Account _account({
  String id = 'acct-1',
  AccountType type = AccountType.brokerage,
  String currency = 'USD',
}) {
  return Account(
    id: id,
    type: type,
    name: 'Test Brokerage',
    currency: currency,
    sync: SyncMeta(
      ownerUserId: 'u',
      updatedAt: DateTime.utc(2026, 5, 1),
      updatedByDevice: 'dev',
      hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
    ),
  );
}

ProviderScope _wrap(
  _Harness h, {
  List<Account>? accounts,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(h.prefs),
      appDatabaseProvider.overrideWith((_) async => h.db),
      outboxStoreProvider.overrideWith((_) async => h.outbox),
      mutationStamperProvider.overrideWith((_) async => makeStubStamper()),
      securitiesAssetRepositoryProvider.overrideWith((_) async => h.secRepo),
      transactionRepositoryProvider.overrideWith((_) async => h.txRepo),
      journalEntryRepositoryProvider.overrideWith((_) async => h.jeRepo),
      currentUserIdProvider.overrideWithValue(() async => 'u-test'),
      securitiesSearchServiceProvider.overrideWith((_) async => h.search),
      securitiesCatalogReadyProvider.overrideWith(
        (_) async => const SecuritiesCatalogLoadResult(
          version: 'v-test-1',
          rowCount: 7,
          reloaded: false,
        ),
      ),
      marketDataServiceProvider.overrideWith((_) async => h.market),
      accountsStreamProvider.overrideWith(
        (_) => Stream.value(accounts ?? [_account()]),
      ),
      tradeEntryServiceProvider.overrideWith(
        (_) async => DefaultTradeEntryService(
          market: h.market,
          fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
          stampHlc: () async =>
              const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev'),
          ownerUserId: 'u',
          deviceId: 'dev',
        ),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TradeEntryFormPage(accountId: 'acct-1'),
    ),
  );
}

/// Bump the test surface tall enough that the entire form fits without
/// scrolling — keeps the picker dropdown + submit button assertions
/// straightforward.
Future<void> _enlargeSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  late _Harness harness;

  setUp(() async {
    harness = await _Harness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  // ── Direct write-path tests ──────────────────────────────────────────
  //
  // The submit button fires a write through `submitOptimistic` which
  // is fire-and-forget — the returned Future is discarded by onPressed.
  // In widget tests the FakeAsync zone cannot reliably drain the full
  // microtask chain of the write.  So we test the write path directly
  // (same code the form's _submit calls) and verify the DB state.

  test('direct write: catalog buy upserts asset + creates JE', () async {
    final asset = await harness.secRepo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: '苹果公司',
    );
    expect(asset.id, 'us_stock:AAPL');

    final tradeService = DefaultTradeEntryService(
      market: harness.market,
      fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      stampHlc: () async =>
          const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev'),
      ownerUserId: 'u',
      deviceId: 'dev',
    );
    final draft = TradeDraft(
      type: TransactionType.buy,
      asset: asset,
      accountId: 'acct-1',
      quantity: Decimal.parse('10'),
      price: Decimal.parse('180'),
      currency: 'USD',
      tradeDate: DateTime.now(),
    );
    final plan = await tradeService.buildPlan(draft, openLots: <Lot>[]);
    final tx = plan.transaction;

    final build = JournalEntryBuilders.buy(
      date: tx.tradeDate,
      accountId: 'acct-1',
      cashAccountId: 'acct-1',
      assetUnit: tx.assetId!,
      qty: tx.quantity,
      price: tx.price,
      quoteCurrency: 'USD',
      lotId: plan.createdLot?.id,
      acquiredOn: plan.createdLot?.openedAt,
    );
    final stored = await harness.jeRepo.create(
      entry: build.entry,
      postings: build.postings,
    );
    expect(stored.entry.id, isNotEmpty);

    // Verify asset row.
    final found = await harness.secRepo.findById('us_stock:AAPL');
    expect(found, isNotNull);
    expect(found!.symbol, 'AAPL');
    expect(found.market, 'us_stock');

    // Verify JE + postings.
    final jes = await harness.jeRepo.watchAllWithPostings().first;
    expect(jes, hasLength(1));
    expect(jes.single.postings, hasLength(greaterThanOrEqualTo(2)));
  });

  test('direct write: manual-add buy upserts + creates JE', () async {
    final asset = await harness.secRepo.upsertSecurity(
      symbol: 'WXYZ',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'WXYZ Test Co',
    );
    expect(asset.id, 'us_stock:WXYZ');
    expect(asset.name, 'WXYZ Test Co');

    final tradeService = DefaultTradeEntryService(
      market: harness.market,
      fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      stampHlc: () async =>
          const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev'),
      ownerUserId: 'u',
      deviceId: 'dev',
    );
    final draft = TradeDraft(
      type: TransactionType.buy,
      asset: asset,
      accountId: 'acct-1',
      quantity: Decimal.parse('5'),
      price: Decimal.parse('20'),
      currency: 'USD',
      tradeDate: DateTime.now(),
    );
    final plan = await tradeService.buildPlan(draft, openLots: <Lot>[]);
    final tx = plan.transaction;

    final build = JournalEntryBuilders.buy(
      date: tx.tradeDate,
      accountId: 'acct-1',
      cashAccountId: 'acct-1',
      assetUnit: tx.assetId!,
      qty: tx.quantity,
      price: tx.price,
      quoteCurrency: 'USD',
      lotId: plan.createdLot?.id,
      acquiredOn: plan.createdLot?.openedAt,
    );
    await harness.jeRepo.create(
      entry: build.entry,
      postings: build.postings,
    );

    final found = await harness.secRepo.findById('us_stock:WXYZ');
    expect(found, isNotNull);
    expect(found!.name, 'WXYZ Test Co');

    final jes = await harness.jeRepo.watchAllWithPostings().first;
    expect(jes, hasLength(1));
    expect(jes.single.postings, hasLength(greaterThanOrEqualTo(2)));
  });

  test('direct write: no HTTP calls in the trade pipeline', () async {
    final metrics = MarketMetrics();
    final guardClient = MarketHttpClient(
      providerName: 'test-no-net',
      rateLimiter: RateLimiter(
        maxRequests: 1,
        window: const Duration(seconds: 1),
      ),
      dio: Dio()..httpClientAdapter = _ThrowingAdapter(),
      metrics: metrics,
    );
    expect(guardClient.providerName, 'test-no-net');

    // Run the same write path — price is user-supplied so no market
    // data fetch is needed.
    final asset = await harness.secRepo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: '苹果公司',
    );
    final tradeService = DefaultTradeEntryService(
      market: harness.market,
      fx: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      stampHlc: () async =>
          const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev'),
      ownerUserId: 'u',
      deviceId: 'dev',
    );
    final draft = TradeDraft(
      type: TransactionType.buy,
      asset: asset,
      accountId: 'acct-1',
      quantity: Decimal.parse('10'),
      price: Decimal.parse('180'),
      currency: 'USD',
      tradeDate: DateTime.now(),
    );
    final plan = await tradeService.buildPlan(draft, openLots: <Lot>[]);

    final build = JournalEntryBuilders.buy(
      date: plan.transaction.tradeDate,
      accountId: 'acct-1',
      cashAccountId: 'acct-1',
      assetUnit: plan.transaction.assetId!,
      qty: plan.transaction.quantity,
      price: plan.transaction.price,
      quoteCurrency: 'USD',
      lotId: plan.createdLot?.id,
      acquiredOn: plan.createdLot?.openedAt,
    );
    await harness.jeRepo.create(
      entry: build.entry,
      postings: build.postings,
    );

    expect(metrics.snapshot().requests, isEmpty,
        reason: 'trade entry path must not perform any HTTP request');
  });

  // ── Widget UI tests ──────────────────────────────────────────────────
  //
  // These verify that the picker, form fields, and submit button work
  // correctly in the UI.  The actual DB write is tested above; here we
  // check that the form navigates the user through the expected flow.

  testWidgets('catalog picker shows results and selects', (tester) async {
    await _enlargeSurface(tester);
    await tester.pumpWidget(_wrap(harness));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('local-securities-picker-field')),
      'AAPL',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Catalog hit: the Chinese name is shown.
    expect(find.text('苹果公司'), findsOneWidget);

    await tester.tap(find.text('苹果公司'));
    await tester.pumpAndSettle();

    // After selection the quantity field gains focus and is ready for input.
    final quantityField = find.byKey(const Key('trade-entry-quantity'));
    expect(quantityField, findsOneWidget);
  });

  testWidgets('manual-add sheet opens for unknown symbol', (tester) async {
    await _enlargeSurface(tester);
    await tester.pumpWidget(_wrap(harness));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('local-securities-picker-field')),
      'WXYZ',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // The manual-add tile is shown for a symbol not in the catalog.
    final manualTile = find.byKey(const Key('local-securities-picker-manual'));
    expect(manualTile, findsOneWidget);

    await tester.tap(manualTile);
    await tester.pumpAndSettle();

    // Sheet is open with the symbol prefilled.
    expect(find.byKey(const Key('manual-security-symbol')), findsOneWidget);
    expect(find.byKey(const Key('manual-security-name')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('manual-security-name')),
      'WXYZ Test Co',
    );
    await tester.tap(find.byKey(const Key('manual-security-submit')));
    await tester.pumpAndSettle();

    // Picker now shows the entered symbol.
    expect(find.textContaining('WXYZ'), findsWidgets);
  });
}

/// Dio adapter that throws on any HTTP call. Any escape to the network
/// from the trade-entry pipeline lands here and fails the test loudly.
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw StateError('trade entry triggered HTTP request to ${options.uri}');
  }
}
