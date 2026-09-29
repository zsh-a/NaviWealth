import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/investment/data/dca_plan_providers.dart';
import 'package:naviwealth/features/finance/investment/data/dca_plan_repository.dart';
import 'package:naviwealth/features/finance/investment/ui/dca_simulator_page.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  for (final mode in [
    'without preview',
    'after failed preview',
    'after changed preview',
  ]) {
    testWidgets('saves current plan $mode', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = DcaPlanRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      final market = _Market(fail: mode == 'after failed preview');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dcaPlanRepositoryProvider.overrideWith((_) async => repository),
            clockProvider.overrideWithValue(const _Clock()),
            marketDataServiceProvider.overrideWith((_) async => market),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            builder: (context, child) => FTheme(
              data: FTheme.neutral.light.desktop,
              child: AppMessenger.init(child: child!),
            ),
            home: const DcaSimulatorPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(DcaSimulatorPage));
      final l10n = AppLocalizations.of(context);
      final container = ProviderScope.containerOf(context);
      expect(market.requests, 0);
      expect(find.text(l10n.dcaSimulatorResultTitle), findsNothing);
      if (mode != 'without preview') {
        await tester.ensureVisible(find.text(l10n.dcaPlanPreviewAction));
        await tester.tap(find.text(l10n.dcaPlanPreviewAction));
        await tester.pumpAndSettle();
        expect(market.requests, greaterThan(0));
        if (mode == 'after changed preview') {
          expect(find.text(l10n.dcaSimulatorResultTitle), findsOneWidget);
        }
      }
      await tester.enterText(
        find.byKey(const ValueKey('dca-symbols')),
        'MSFT:60 QQQ:40',
      );
      await tester.enterText(find.byKey(const ValueKey('dca-amount')), '750');
      await tester.pumpAndSettle();
      if (mode == 'after changed preview') {
        expect(find.text(l10n.dcaSimulatorParametersChanged), findsOneWidget);
      }
      final save = find.byKey(const ValueKey('dca-plan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final plan = container.read(dcaPlansProvider).requireValue.single;
      expect(plan.allocations.map((a) => a.symbol), ['MSFT', 'QQQ']);
      expect(plan.allocations.map((a) => a.weight), [
        Decimal.parse('0.6'),
        Decimal.parse('0.4'),
      ]);
      expect(plan.amountPerContribution, Decimal.fromInt(750));
      expect(plan.currency, 'USD');
      expect(plan.market, AssetMarket.usStock);
      if (mode == 'without preview') expect(market.requests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

class _Clock implements Clock {
  const _Clock();
  @override
  DateTime now() => DateTime.utc(2026, 5, 18);
  @override
  Future<void> sleep(Duration duration) async {}
}

class _Market implements MarketDataService {
  _Market({this.fail = false});
  final bool fail;
  int requests = 0;
  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    requests++;
    if (fail) throw StateError('offline');
    return MarketResponse(
      data: [
        for (var i = 0; i < 18; i++)
          HistoricalBar(
            symbol: symbol,
            asOf: DateTime.utc(2024, 1 + i),
            open: Decimal.fromInt(100 + i),
            high: Decimal.fromInt(102 + i),
            low: Decimal.fromInt(98 + i),
            close: Decimal.fromInt(100 + i),
          ),
      ],
      freshness: DataFreshness.cachedFresh,
      source: 'test',
      fetchedAt: to,
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) => throw UnimplementedError();
  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) => throw UnimplementedError();
}
