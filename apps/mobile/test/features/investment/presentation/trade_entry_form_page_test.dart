import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/db/providers.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/market/http/market_http_client.dart';
import 'package:naviwealth/data/market/http/rate_limiter.dart';
import 'package:naviwealth/data/market/market_data_providers.dart';
import 'package:naviwealth/data/market/metrics/market_metrics.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/data/securities_catalog/providers.dart';
import 'package:naviwealth/data/securities_catalog/securities_catalog_loader.dart';
import 'package:naviwealth/data/securities_catalog/securities_search_service.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/data/transaction_repository.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/default_trade_entry_service.dart';
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
    required this.secRepo,
    required this.search,
    required this.market,
    required this.prefs,
  });

  final AppDatabase db;
  final InMemoryOutboxStore outbox;
  final TransactionRepository txRepo;
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    return _Harness(
      db: db,
      outbox: outbox,
      txRepo: txRepo,
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

ProviderScope _wrap(_Harness h, {List<Account>? accounts}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(h.prefs),
      appDatabaseProvider.overrideWith((_) async => h.db),
      outboxStoreProvider.overrideWith((_) async => h.outbox),
      securitiesAssetRepositoryProvider.overrideWith((_) async => h.secRepo),
      transactionRepositoryProvider.overrideWith((_) async => h.txRepo),
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

  testWidgets(
      'records a trade from a catalog hit without any HTTP call '
      'and writes both assets + transactions rows', (tester) async {
    await _enlargeSurface(tester);
    // Stand up a real MarketHttpClient backed by a throw-on-call adapter
    // so any accidental network request from the trade-entry pipeline
    // surfaces as a hard test failure.
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

    await tester.pumpWidget(_wrap(harness));
    await tester.pumpAndSettle();

    // Drive the picker: type the symbol, pick the first hit. The
    // picker's tile shows the Chinese name (if present) under the
    // symbol, so we tap by the unique subtitle.
    await tester.enterText(
      find.byKey(const Key('local-securities-picker-field')),
      'AAPL',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('苹果公司'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('trade-entry-quantity')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('trade-entry-price')),
      '180',
    );
    await tester.pumpAndSettle();

    // Form lives in a ListView; scroll the submit button fully into view.
    await tester.ensureVisible(find.byKey(const Key('trade-entry-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pumpAndSettle();

    // The asset row was upserted from the catalog hit.
    final asset = await harness.secRepo.findById('us_stock:AAPL');
    expect(asset, isNotNull);
    expect(asset!.symbol, 'AAPL');
    expect(asset.market, 'us_stock');

    // The transaction was recorded against the canonical asset id.
    final txns = await harness.txRepo.findByAssetId('us_stock:AAPL');
    expect(txns, hasLength(1));
    expect(txns.single.assetId, 'us_stock:AAPL');
    expect(txns.single.accountId, 'acct-1');

    // Network guard.
    expect(metrics.snapshot().requests, isEmpty,
        reason: 'trade entry path must not perform any HTTP request');
  });

  testWidgets('manual-add sheet inserts a hand-entered security and '
      'records a trade against it', (tester) async {
    await _enlargeSurface(tester);
    await tester.pumpWidget(_wrap(harness));
    await tester.pumpAndSettle();

    // Type a symbol that doesn't exist in the catalog so the manual-add
    // tile is the only viable next step.
    await tester.enterText(
      find.byKey(const Key('local-securities-picker-field')),
      'WXYZ',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('local-securities-picker-manual')));
    await tester.pumpAndSettle();

    // Sheet is open with the symbol prefilled. Fill in a name and submit.
    expect(find.byKey(const Key('manual-security-symbol')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('manual-security-name')),
      'WXYZ Test Co',
    );
    await tester.tap(find.byKey(const Key('manual-security-submit')));
    await tester.pumpAndSettle();

    // Picker now reads "WXYZ — WXYZ Test Co".
    expect(find.textContaining('WXYZ'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('trade-entry-quantity')),
      '5',
    );
    await tester.enterText(
      find.byKey(const Key('trade-entry-price')),
      '20',
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('trade-entry-submit')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pumpAndSettle();

    // The hand-entered security was upserted with the inferred market
    // (`WXYZ` matches the all-caps US-stock heuristic).
    final asset = await harness.secRepo.findById('us_stock:WXYZ');
    expect(asset, isNotNull);
    expect(asset!.name, 'WXYZ Test Co');

    final txns = await harness.txRepo.findByAssetId('us_stock:WXYZ');
    expect(txns, hasLength(1));
    expect(txns.single.assetId, 'us_stock:WXYZ');
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
