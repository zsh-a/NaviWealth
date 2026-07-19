import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/asset_search_hit.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/providers.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/securities_search_service.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_prefill.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/investment/ui/trade_entry_form_page.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

class _FakeSearch extends SecuritiesSearchService {
  _FakeSearch({required super.db});

  @override
  Future<List<AssetSearchHit>> searchLocal(
    String query, {
    int limit = 20,
    AssetMarket? market,
  }) async {
    return const [
      AssetSearchHit(
        id: 'us_stock:AAPL',
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        type: AssetType.stock,
        currency: 'USD',
        source: AssetSearchHitSource.catalog,
        match: AssetSearchHitMatch.exact,
        rank: 0,
        nameEn: 'Apple',
      ),
    ];
  }
}

Account _account({
  required String id,
  required String name,
  required AccountCategory type,
  String currency = 'CHF',
}) {
  return Account(
    id: id,
    type: type,
    name: name,
    currency: currency,
    category: AccountSide.asset,
    sync: SyncMeta(
      ownerUserId: 'u-test',
      updatedAt: DateTime.utc(2026),
      updatedByDevice: 'dev-test',
      hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
    ),
  );
}

Widget _wrap(Widget child, {TextScaler? textScaler}) {
  return MaterialApp(
    builder: (context, child) {
      Widget content = FTheme(data: FThemes.slate.light.desktop, child: child!);
      if (textScaler != null) {
        content = MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: content,
        );
      }
      return AppMessenger.init(child: content);
    },
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: child,
  );
}

TradeEntrySubmissionService _submissionService(
  AppDatabase db, {
  TradeEntryService tradeService = const _UiTradeEntryService(),
}) {
  final outbox = DriftOutboxStore(db);
  final stamper = makeStubStamper();
  return TradeEntrySubmissionService(
    db: db,
    securitiesRepo: SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    ),
    tradeService: tradeService,
    journalEntryRepo: JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'USD',
    ),
    priceRepo: PriceRepository(db: db, outbox: outbox, stamper: stamper),
    currentUserId: () async => 'u-test',
  );
}

Future<void> _pumpReadyTradeForm(
  WidgetTester tester, {
  required AppDatabase db,
  required TradeEntrySubmissionService service,
  bool withCashDefault = false,
}) async {
  SharedPreferences.setMockInitialValues(
    withCashDefault ? {'naviwealth.forms.trade.cashAccount': 'cash'} : const {},
  );
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) async => db),
        accountsStreamProvider.overrideWith(
          (_) => Stream.value([
            _account(
              id: 'broker',
              name: 'Broker',
              type: AccountCategory.broker,
              currency: 'USD',
            ),
            if (withCashDefault)
              _account(
                id: 'cash',
                name: 'Cash',
                type: AccountCategory.cash,
                currency: 'USD',
              ),
          ]),
        ),
        securitiesSearchServiceProvider.overrideWith(
          (_) async => _FakeSearch(db: db),
        ),
        tradeEntrySubmissionServiceProvider.overrideWith((_) async => service),
      ],
      child: _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TradeEntryFormPage(
                  accountId: 'broker',
                  prefill: TradeEntryPrefill(
                    type: TradeType.valuationAdjust,
                    quantity: Decimal.one,
                    price: Decimal.fromInt(150),
                    currency: 'USD',
                  ),
                ),
              ),
            ),
            child: const Text('Open trade'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open trade'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('symbol-field-search')), 'AAPL');
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
  await tester.tap(find.text('AAPL').last);
  await tester.pumpAndSettle();
}

Future<void> _pressControlEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('requires a brokerage account instead of accepting cash', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _account(
                id: 'cash',
                name: 'Cash',
                type: AccountCategory.cash,
                currency: 'CNY',
              ),
            ]),
          ),
          securitiesSearchServiceProvider.overrideWith(
            (_) async => _FakeSearch(db: db),
          ),
        ],
        child: _wrap(const TradeEntryFormPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Brokerage account required'), findsOneWidget);
    expect(
      find.text(
        'Create a brokerage or crypto account before recording a securities trade.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('trade-entry-account')), findsNothing);
    expect(find.text('New account'), findsOneWidget);
  });

  testWidgets('contextual trade prefills asset, side, and compact settlement', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final outbox = DriftOutboxStore(db);
    final repo = SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
    final asset = await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'Apple',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _account(
                id: 'broker',
                name: 'Broker',
                type: AccountCategory.broker,
                currency: 'USD',
              ),
            ]),
          ),
          securitiesAssetRepositoryProvider.overrideWith((_) async => repo),
          securitiesSearchServiceProvider.overrideWith(
            (_) async => _FakeSearch(db: db),
          ),
        ],
        child: _wrap(
          TradeEntryFormPage(
            assetId: asset.id,
            accountId: 'broker',
            initialType: TradeType.sell,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AAPL — Apple'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('USD cash in holding account'), findsOneWidget);
    final settlementToggle = find.byKey(
      const Key('trade-entry-settlement-toggle-label'),
    );
    expect(
      tester.widget<Semantics>(settlementToggle).properties.expanded,
      isFalse,
    );
    expect(
      find.byKey(const Key('trade-entry-settlement-details')).hitTestable(),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('trade-entry-settlement-summary')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('trade-entry-settlement-details')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.widget<Semantics>(settlementToggle).properties.expanded,
      isTrue,
    );
  });

  testWidgets('trade details stay accessible and stack costs for large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _account(
                id: 'broker',
                name: 'Broker',
                type: AccountCategory.broker,
                currency: 'USD',
              ),
            ]),
          ),
          securitiesSearchServiceProvider.overrideWith(
            (_) async => _FakeSearch(db: db),
          ),
        ],
        child: _wrap(
          const TradeEntryFormPage(accountId: 'broker'),
          textScaler: const TextScaler.linear(2),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('trade-entry-advanced-toggle-label'));
    expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);
    expect(
      tester
          .widget<Offstage>(
            find.byKey(const Key('trade-entry-advanced-details')),
          )
          .offstage,
      isTrue,
    );

    await tester.ensureVisible(find.text('Trade details'));
    await tester.tap(find.text('Trade details'));
    await tester.pumpAndSettle();

    expect(tester.widget<Semantics>(toggle).properties.expanded, isTrue);
    expect(
      tester
          .widget<Offstage>(
            find.byKey(const Key('trade-entry-advanced-details')),
          )
          .offstage,
      isFalse,
    );
    final fee = find.byKey(const Key('trade-entry-fee'));
    final tax = find.byKey(const Key('trade-entry-tax'));
    await tester.ensureVisible(fee);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(tax).dy,
      greaterThan(tester.getBottomLeft(fee).dy),
    );

    final feeInput = find.descendant(
      of: fee,
      matching: find.byType(FTextFormField),
    );
    await tester.enterText(feeInput, '3.25');
    await tester.ensureVisible(find.text('Trade details'));
    await tester.tap(find.text('Trade details'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);
    await tester.tap(find.text('Trade details'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: fee, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      '3.25',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('preflight timeout keeps the trade form retryable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'naviwealth.forms.trade.cashAccount': 'cash',
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    var providerReads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _account(
                id: 'broker',
                name: 'Broker',
                type: AccountCategory.broker,
                currency: 'USD',
              ),
              _account(
                id: 'cash',
                name: 'Cash',
                type: AccountCategory.cash,
                currency: 'USD',
              ),
            ]),
          ),
          securitiesSearchServiceProvider.overrideWith(
            (_) async => _FakeSearch(db: db),
          ),
          tradeEntrySubmissionServiceProvider.overrideWith((_) async {
            providerReads += 1;
            return Completer<TradeEntrySubmissionService>().future;
          }),
          tradeEntryPreflightTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
        child: _wrap(
          TradeEntryFormPage(
            accountId: 'broker',
            prefill: TradeEntryPrefill(
              type: TradeType.buy,
              quantity: Decimal.one,
              price: Decimal.parse('10'),
              currency: 'USD',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('symbol-field-search')),
      'AAPL',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AAPL').last);
    await tester.pumpAndSettle();
    expect(find.text('AAPL — Apple'), findsOneWidget);

    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TradeEntryFormPage), findsOneWidget);
    expect(providerReads, 1);
    expect(find.text('AAPL — Apple'), findsOneWidget);
    expect(find.textContaining("Couldn't record trade"), findsOneWidget);
    final submit = tester.widget<FButton>(
      find.byKey(const Key('trade-entry-submit')),
    );
    expect(submit.onPress, isNotNull);
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(providerReads, 2);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('new trade starts in base currency, not a stale remembered one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'naviwealth.forms.trade.currency': 'CHF',
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _account(
                id: 'broker',
                name: 'Broker',
                type: AccountCategory.broker,
              ),
              _account(id: 'cash', name: 'Cash', type: AccountCategory.cash),
            ]),
          ),
          securitiesSearchServiceProvider.overrideWith(
            (_) async => SecuritiesSearchService(db: db),
          ),
        ],
        child: _wrap(const TradeEntryFormPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('trade-entry-settlement-summary')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CurrencyPicker>(find.byKey(const Key('trade-entry-currency')))
          .value,
      'CNY',
    );
  });

  testWidgets(
    'remembered cash waits for the asset currency before validation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'naviwealth.forms.trade.cashAccount': 'cash',
      });
      final prefs = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWith((_) async => db),
            accountsStreamProvider.overrideWith(
              (_) => Stream.value([
                _account(
                  id: 'broker',
                  name: 'Broker',
                  type: AccountCategory.broker,
                  currency: 'USD',
                ),
                _account(
                  id: 'cash',
                  name: 'Cash USD',
                  type: AccountCategory.cash,
                  currency: 'USD',
                ),
              ]),
            ),
            securitiesSearchServiceProvider.overrideWith(
              (_) async => _FakeSearch(db: db),
            ),
          ],
          child: _wrap(const TradeEntryFormPage(accountId: 'broker')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trade-entry-settlement-summary')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountPicker>(
              find.byKey(const Key('trade-entry-cash-account')),
            )
            .value,
        'cash',
      );
      tester
          .widget<SymbolField>(find.byType(SymbolField))
          .onChanged
          ?.call(
            const LocalSecurityChoice(
              symbol: 'AAPL',
              market: AssetMarket.usStock,
              type: AssetType.stock,
              currency: 'USD',
              fromCatalog: true,
            ),
          );
      await tester.pump();

      expect(
        tester
            .widget<AccountPicker>(
              find.byKey(const Key('trade-entry-cash-account')),
            )
            .value,
        'cash',
      );
      expect(find.textContaining('previous cash account'), findsNothing);
    },
  );

  testWidgets('applies upstream trade-entry prefill as pristine defaults', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _account(
                id: 'broker',
                name: 'Broker',
                type: AccountCategory.broker,
                currency: 'CNY',
              ),
              _account(
                id: 'cash',
                name: 'Cash',
                type: AccountCategory.cash,
                currency: 'CNY',
              ),
            ]),
          ),
          securitiesSearchServiceProvider.overrideWith(
            (_) async => SecuritiesSearchService(db: db),
          ),
        ],
        child: _wrap(
          TradeEntryFormPage(
            prefill: TradeEntryPrefill(
              type: TradeType.sell,
              quantity: Decimal.one,
              price: Decimal.parse('1250.75'),
              currency: 'CNY',
              fee: Decimal.parse('1.25'),
              tax: Decimal.parse('2.50'),
              note: 'Rebalance suggestion',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('1250.75'), findsOneWidget);
    await tester.tap(find.text('Trade details'));
    await tester.pumpAndSettle();
    expect(find.text('1.25'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    expect(find.text('Rebalance suggestion'), findsOneWidget);
  });

  testWidgets('trade segments keep adjustments out of the entry flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _pumpReadyTradeForm(tester, db: db, service: _submissionService(db));

    expect(find.byType(SegmentedRow<TradeType>), findsOneWidget);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('Adjust'), findsNothing);
    expect(find.text('Trade details'), findsOneWidget);

    await tester.tap(find.text('Trade details'));
    await tester.pumpAndSettle();
    expect(find.text('Fee'), findsOneWidget);
    expect(find.text('Tax'), findsOneWidget);
  });

  testWidgets('explicit currency wins and clears incompatible cash account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _pumpReadyTradeForm(
      tester,
      db: db,
      service: _submissionService(db),
      withCashDefault: true,
    );

    tester
        .widget<SegmentedRow<TradeType>>(find.byType(SegmentedRow<TradeType>))
        .onChanged(TradeType.buy);
    await tester.pump();
    await tester.tap(find.byKey(const Key('trade-entry-settlement-summary')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AccountPicker>(
            find.byKey(const Key('trade-entry-cash-account')),
          )
          .value,
      'cash',
    );

    tester
        .widget<CurrencyPicker>(find.byKey(const Key('trade-entry-currency')))
        .onChanged('CNY');
    await tester.pump();
    expect(
      tester
          .widget<AccountPicker>(
            find.byKey(const Key('trade-entry-cash-account')),
          )
          .value,
      isNull,
    );
    expect(
      find.text(
        'The previous cash account does not support this currency. '
        'Pick another cash account.',
      ),
      findsOneWidget,
    );

    tester
        .widget<SymbolField>(find.byType(SymbolField))
        .onChanged
        ?.call(
          const LocalSecurityChoice(
            symbol: 'AAPL',
            market: AssetMarket.usStock,
            type: AssetType.stock,
            currency: 'USD',
            fromCatalog: true,
          ),
        );
    await tester.pump();
    expect(
      tester
          .widget<CurrencyPicker>(find.byKey(const Key('trade-entry-currency')))
          .value,
      'CNY',
    );
  });

  testWidgets('lot currency mismatch is localized and actionable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _pumpReadyTradeForm(
      tester,
      db: db,
      service: _submissionService(
        db,
        tradeService: const _LotMismatchUiTradeService(),
      ),
    );

    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Change the visible Currency field'),
      findsOneWidget,
    );
    expect(find.textContaining('repair or split the holding'), findsOneWidget);
    expect(find.textContaining('lotCurrencyMismatch'), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('successful trade offers Undo for journal and price', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _seedBrokerAccount(db);
    final service = _submissionService(db);
    await _pumpReadyTradeForm(tester, db: db, service: service);

    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsOneWidget);
    expect(await db.select(db.assets).get(), hasLength(1));
    expect(await db.select(db.journalEntries).get(), hasLength(1));
    expect(await db.select(db.postings).get(), hasLength(2));
    expect(await db.select(db.prices).get(), hasLength(1));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(
      (await db.select(db.journalEntries).getSingle()).deletedAt,
      isNotNull,
    );
    expect(
      (await db.select(db.postings).get()).every(
        (posting) => posting.deletedAt != null,
      ),
      isTrue,
    );
    expect((await db.select(db.prices).getSingle()).deletedAt, isNotNull);
    expect((await db.select(db.assets).getSingle()).deletedAt, isNull);
    expect(find.text('Change undone'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('keyboard submit stays disabled while one trade is in flight', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _seedBrokerAccount(db);
    final trades = _BlockingUiTradeService();
    final service = _submissionService(db, tradeService: trades);
    await _pumpReadyTradeForm(tester, db: db, service: service);

    await _pressControlEnter(tester);
    for (var i = 0; i < 5 && trades.calls == 0; i++) {
      await tester.pump();
    }
    expect(trades.calls, 1);
    expect(
      tester
          .widget<FButton>(find.byKey(const Key('trade-entry-submit')))
          .onPress,
      isNull,
    );

    await _pressControlEnter(tester);
    await _pressControlEnter(tester);
    expect(trades.calls, 1);

    trades.release();
    await tester.pumpAndSettle();
    expect(await db.select(db.journalEntries).get(), hasLength(1));
  });

  testWidgets('trade Undo conflict exposes safe repeated Retry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _seedBrokerAccount(db);
    final service = _submissionService(db);
    await _pumpReadyTradeForm(tester, db: db, service: service);

    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pumpAndSettle();

    final committedPrice = await db.select(db.prices).getSingle();
    await (db.update(
      db.prices,
    )..where((row) => row.id.equals(committedPrice.id))).write(
      PricesCompanion(
        perUnit: Value(Decimal.fromInt(175)),
        updatedAt: Value(DateTime.utc(2027)),
        updatedByDevice: const Value('remote'),
        hlc: const Value(Hlc(wallMillis: 21_000, counter: 0, nodeId: 'remote')),
      ),
    );

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Couldn't undo the change. Try again."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Change undone'), findsNothing);
    expect(
      (await db.select(db.prices).getSingle()).perUnit,
      Decimal.fromInt(175),
    );
    expect((await db.select(db.journalEntries).getSingle()).deletedAt, isNull);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Couldn't undo the change. Try again."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Change undone'), findsNothing);
    expect(
      (await db.select(db.prices).getSingle()).perUnit,
      Decimal.fromInt(175),
    );
    expect((await db.select(db.journalEntries).getSingle()).deletedAt, isNull);
    expect(
      (await db.select(db.postings).get()).every(
        (posting) => posting.deletedAt == null,
      ),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('failed form retry reuses one stable transaction id', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _seedBrokerAccount(db);
    final trades = _FailOnceUiTradeService();
    final service = _submissionService(db, tradeService: trades);
    await _pumpReadyTradeForm(tester, db: db, service: service);

    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pumpAndSettle();
    expect(await db.select(db.journalEntries).get(), isEmpty);

    await tester.tap(find.byKey(const Key('trade-entry-submit')));
    await tester.pumpAndSettle();

    expect(await db.select(db.journalEntries).get(), hasLength(1));
    expect(trades.transactionIds, hasLength(3));
    expect(trades.transactionIds.toSet(), hasLength(1));
    expect(
      (await db.select(db.journalEntries).getSingle()).id,
      trades.transactionIds.first,
    );
  });
}

Future<void> _seedBrokerAccount(AppDatabase db) => db
    .into(db.accounts)
    .insert(
      AccountsCompanion.insert(
        id: 'broker',
        type: AccountCategory.broker,
        name: 'Broker',
        currency: 'USD',
        category: const Value(AccountSide.asset),
        ownerUserId: 'u-test',
        updatedAt: DateTime.utc(2026),
        updatedByDevice: 'dev-test',
        hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
      ),
    );

class _UiTradeEntryService implements TradeEntryService {
  const _UiTradeEntryService();

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    return TradeEntryPlan(
      trade: PlannedTrade(
        id: draft.transactionId!,
        accountId: draft.accountId,
        assetId: draft.asset.id,
        type: draft.type,
        quantity: draft.quantity,
        price: draft.price ?? Decimal.one,
        currency: draft.currency,
        tradeDate: draft.tradeDate,
        fee: draft.fee,
        tax: draft.tax,
        note: draft.note,
      ),
      pricing: PriceProvenance.userSupplied,
    );
  }
}

final class _LotMismatchUiTradeService extends _UiTradeEntryService {
  const _LotMismatchUiTradeService();

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    throw const TradeSubmissionContractError(
      TradeSubmissionContractErrorCode.lotCurrencyMismatch,
      'technical lot currency details must stay private',
    );
  }
}

final class _FailOnceUiTradeService extends _UiTradeEntryService {
  final List<String> transactionIds = [];
  var _failed = false;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    transactionIds.add(draft.transactionId!);
    if (!_failed) {
      _failed = true;
      throw StateError('injected first-attempt failure');
    }
    return super.buildPlan(draft, openLots: openLots);
  }
}

final class _BlockingUiTradeService extends _UiTradeEntryService {
  final Completer<void> _gate = Completer<void>();
  var calls = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    calls += 1;
    await _gate.future;
    return super.buildPlan(draft, openLots: openLots);
  }
}
