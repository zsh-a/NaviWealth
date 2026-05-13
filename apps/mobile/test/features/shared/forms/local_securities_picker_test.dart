import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/securities_catalog/asset_search_hit.dart';
import 'package:naviwealth/data/securities_catalog/securities_search_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/shared/forms/local_securities_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../data/db/test_database.dart';

class _FakeSearch extends SecuritiesSearchService {
  _FakeSearch(AppDatabase db) : super(db: db);

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
        nameEn: 'Apple Inc.',
        nameCn: '苹果公司',
      ),
    ];
  }
}

Widget _wrap({
  required AppDatabase db,
  required GlobalKey<FormState> formKey,
  required ValueChanged<LocalSecurityChoice?> onSelected,
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
          child: LocalSecuritiesPicker(
            search: _FakeSearch(db),
            onSelected: onSelected,
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
        db: db,
        formKey: formKey,
        onSelected: (choice) => selected = choice,
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('local-securities-picker-field')),
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
}
