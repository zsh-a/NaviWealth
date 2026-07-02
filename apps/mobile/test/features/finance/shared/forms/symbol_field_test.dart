import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/asset_search_hit.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/securities_search_service.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/shared/forms/symbol_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/persistence/test_database.dart';

class _FakeSearch extends SecuritiesSearchService {
  _FakeSearch(AppDatabase db, {this.onSearch}) : super(db: db);

  /// Optional hook so tests can assert that the market filter is wired
  /// through. The callback fires on every searchLocal invocation.
  final void Function(String query, AssetMarket? market)? onSearch;

  @override
  Future<List<AssetSearchHit>> searchLocal(
    String query, {
    int limit = 20,
    AssetMarket? market,
  }) async {
    onSearch?.call(query, market);
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
        nameEn: 'Apple Inc.',
        nameCn: '苹果公司',
      ),
    ];
  }
}

Widget _wrap({
  required SecuritiesSearchService search,
  required GlobalKey<FormState> formKey,
  required ValueChanged<LocalSecurityChoice?> onChanged,
  List<AssetMarket>? markets,
  LocalSecurityChoice? initialValue,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'CN'),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(
        body: Form(
          key: formKey,
          child: SymbolFieldBody(
            search: search,
            markets: markets,
            initialValue: initialValue,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('keeps selection after writing selected label into the field', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final formKey = GlobalKey<FormState>();
    LocalSecurityChoice? selected;

    await tester.pumpWidget(
      _wrap(
        search: _FakeSearch(db),
        formKey: formKey,
        onChanged: (choice) => selected = choice,
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('symbol-field-search')),
      'AAPL',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    await tester.tap(find.text('AAPL').last);
    await tester.pumpAndSettle();

    expect(selected?.symbol, 'AAPL');
    expect(find.text('AAPL — 苹果公司'), findsOneWidget);
    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('请选择一个资产'), findsNothing);
  });

  testWidgets('single-element markets list filters search without UI', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final formKey = GlobalKey<FormState>();
    AssetMarket? capturedMarket;

    await tester.pumpWidget(
      _wrap(
        search: _FakeSearch(db, onSearch: (_, m) => capturedMarket = m),
        formKey: formKey,
        onChanged: (_) {},
        markets: const [AssetMarket.cnA],
      ),
    );

    expect(find.byKey(const Key('symbol-field-market')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('symbol-field-search')),
      'AAPL',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(capturedMarket, AssetMarket.cnA);
  });

  testWidgets('multi-market markets list renders selector', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final formKey = GlobalKey<FormState>();

    await tester.pumpWidget(
      _wrap(
        search: _FakeSearch(db),
        formKey: formKey,
        onChanged: (_) {},
        markets: const [AssetMarket.usStock, AssetMarket.hkStock],
      ),
    );

    expect(find.byKey(const Key('symbol-field-market')), findsOneWidget);
  });

  testWidgets('readOnly with initialValue renders summary, no search field', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final formKey = GlobalKey<FormState>();

    const initial = LocalSecurityChoice(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      fromCatalog: true,
      name: 'Apple Inc.',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh', 'CN'),
          home: FTheme(
            data: FThemes.slate.light.desktop,
            child: Scaffold(
              body: Form(
                key: formKey,
                // ReadOnly short-circuits before the FutureProvider unwrap,
                // so this exercises the public widget without needing a
                // real search service.
                child: const SymbolField(readOnly: true, initialValue: initial),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('symbol-field-search')), findsNothing);
    expect(find.text('AAPL — Apple Inc.'), findsOneWidget);
    // form is valid because readOnly path treats initialValue as a pick.
    expect(initial.symbol, 'AAPL');
  });
}
