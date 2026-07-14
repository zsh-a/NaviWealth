import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/data/asset_detail_providers.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_trend_mini_chart_card.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('distant cost basis does not flatten the observed price trend', (
    tester,
  ) async {
    await _pumpChart(tester, costBasis: 20);

    final chart = tester.widget<NwLineChart>(find.byType(NwLineChart));
    expect(chart.series, hasLength(1));
    expect(chart.series.single.points.map((point) => point.y), [748, 750, 752]);
    expect(chart.yAxis.showGrid, isTrue);
    expect(chart.heroDots, isTrue);
    expect(chart.showTouchXAxisLabel, isTrue);
    expect(find.textContaining('0.53%'), findsOneWidget);
    expect(find.text('Cost basis'), findsNothing);
  });

  testWidgets('nearby cost basis remains a labeled chart reference', (
    tester,
  ) async {
    await _pumpChart(tester, costBasis: 749, width: 320, textScale: 1.5);

    final chart = tester.widget<NwLineChart>(find.byType(NwLineChart));
    expect(chart.series, hasLength(2));
    expect(chart.series.last.emphasis, SeriesEmphasis.dashed);
    expect(chart.series.last.fillOpacity, AppOpacity.transparent);
    expect(chart.heroDots, isFalse);
    expect(find.text('Cost basis'), findsOneWidget);
    expect(find.text(r'$749.00'), findsOneWidget);
  });
}

Future<void> _pumpChart(
  WidgetTester tester, {
  required int costBasis,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final snapshot = HoldingSnapshot(
    assetId: _asset.id,
    quantity: Decimal.one,
    costBasisInAssetCurrency: Decimal.fromInt(costBasis),
    marketValueInAssetCurrency: Decimal.fromInt(752),
    assetCurrency: 'USD',
    costBasisInBase: Decimal.fromInt(costBasis),
    marketValueInBase: Decimal.fromInt(752),
    unrealizedPnlInBase: Decimal.fromInt(752 - costBasis),
    weight: Decimal.zero,
    baseCurrency: 'USD',
    asOf: DateTime.utc(2026, 7, 13),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        assetPriceHistoryProvider.overrideWith(
          (ref, key) async => _historyResponse(),
        ),
        assetHoldingSnapshotProvider.overrideWith(
          (ref, assetId) async => snapshot,
        ),
      ],
      child: FTheme(
        data: FThemes.slate.light.desktop,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: AssetTrendMiniChartCard(asset: _asset),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MarketResponse<List<HistoricalBar>> _historyResponse() {
  return MarketResponse<List<HistoricalBar>>(
    data: [
      _bar(DateTime.utc(2026, 7, 11), 748),
      _bar(DateTime.utc(2026, 7, 12), 750),
      _bar(DateTime.utc(2026, 7, 13), 752),
    ],
    freshness: DataFreshness.live,
    source: 'test',
    fetchedAt: DateTime.utc(2026, 7, 13),
  );
}

HistoricalBar _bar(DateTime asOf, int close) {
  final price = Decimal.fromInt(close);
  return HistoricalBar(
    symbol: _asset.symbol,
    asOf: asOf,
    open: price,
    high: price,
    low: price,
    close: price,
  );
}

final _asset = Asset(
  id: 'us_stock:SPY',
  type: AssetType.etf,
  symbol: 'SPY',
  currency: 'USD',
  name: 'S&P 500 ETF',
  market: 'us_stock',
  sync: SyncMeta(
    ownerUserId: 'u-test',
    updatedAt: DateTime.utc(2026),
    updatedByDevice: 'dev-test',
    hlc: Hlc.zero('dev-test'),
  ),
);
