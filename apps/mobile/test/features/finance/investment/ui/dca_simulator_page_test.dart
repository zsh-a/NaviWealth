import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/investment/application/dca_simulation_service.dart';
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
  testWidgets(
    'changed parameters require rerun and save the exact weighted result',
    (tester) async {
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dcaPlanRepositoryProvider.overrideWith((_) async => repository),
            clockProvider.overrideWithValue(const _Clock()),
            marketDataServiceProvider.overrideWith(
              (_) async => const _Market(),
            ),
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
      final page = find.byType(DcaSimulatorPage);
      final context = tester.element(page);
      final l10n = AppLocalizations.of(context);
      final container = ProviderScope.containerOf(context);
      final save = find.widgetWithText(FButton, l10n.dcaSimulatorDraftAction);
      expect(find.text(l10n.dcaSimulatorResultTitle), findsOneWidget);
      expect(find.byType(FTextField), findsNothing);

      await tester.tap(find.text(l10n.dcaSimulatorParametersTitle));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dca-symbols')),
        'MSFT:60 QQQ:40',
      );
      await tester.enterText(find.byKey(const ValueKey('dca-amount')), '750');
      await tester.pumpAndSettle();
      expect(find.text(l10n.dcaSimulatorParametersChanged), findsOneWidget);
      await tester.ensureVisible(save);
      expect(tester.widget<FButton>(save).onPress, isNull);
      expect(container.read(dcaPlansProvider).requireValue, isEmpty);

      // Collapsing parameters must keep the old result and its warning visible.
      await tester.ensureVisible(find.text(l10n.dcaSimulatorParametersTitle));
      await tester.tap(find.text(l10n.dcaSimulatorParametersTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dcaSimulatorResultTitle), findsOneWidget);
      expect(find.text(l10n.dcaSimulatorParametersChanged), findsOneWidget);
      await tester.tap(find.text(l10n.dcaSimulatorParametersTitle));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.dcaSimulatorRunAction));
      await tester.tap(find.text(l10n.dcaSimulatorRunAction));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dcaSimulatorParametersChanged), findsNothing);
      expect(find.byType(FTextField), findsNothing);
      final simulation = container.read(dcaSimulationProvider).requireValue;
      expect(simulation.request.amountPerContribution, Decimal.fromInt(750));
      expect(simulation.request.symbols, ['MSFT', 'QQQ']);
      expect(
        simulation.result.positions.first.invested,
        simulation.result.totalInvested * Decimal.parse('0.6'),
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final plan = container.read(dcaPlansProvider).requireValue.single;
      expect(plan.allocations.map((a) => a.symbol), ['MSFT', 'QQQ']);
      expect(plan.allocations.map((a) => a.weight), [
        Decimal.parse('0.6'),
        Decimal.parse('0.4'),
      ]);
      expect(
        plan.amountPerContribution,
        simulation.request.amountPerContribution,
      );
      expect(plan.currency, simulation.request.currency);
      expect(plan.market, simulation.request.market);
      expect(plan.frequency, simulation.request.frequency);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _Clock implements Clock {
  const _Clock();
  @override
  DateTime now() => DateTime.utc(2026, 5, 18);
  @override
  Future<void> sleep(Duration duration) async {}
}

class _Market implements MarketDataService {
  const _Market();
  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async => MarketResponse(
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
