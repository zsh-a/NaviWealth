import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/market/exceptions.dart';
import 'package:naviwealth/data/market/market_data_providers.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/shared/forms/local_securities_picker.dart';
import 'package:naviwealth/features/shared/forms/manual_security_sheet.dart';

/// Configurable [MarketDataService] stub for the FIR-78 enrichment tests.
///
/// Either returns [searchResults] or throws [searchError] when
/// `searchSymbol` is called, mirroring the live composite service which
/// surfaces a `NoMarketDataAvailableException` once every provider has
/// failed.
class _ConfigurableMarket implements MarketDataService {
  _ConfigurableMarket({this.searchResults = const [], this.searchError});

  final List<SymbolInfo> searchResults;
  final Object? searchError;

  int searchCalls = 0;
  String? lastQuery;
  AssetMarket? lastMarketHint;

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) async {
    searchCalls++;
    lastQuery = query;
    lastMarketHint = market;
    if (searchError != null) {
      throw searchError!;
    }
    return MarketResponse(
      data: searchResults,
      freshness: DataFreshness.live,
      source: 'stub',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(String symbol, {AssetMarket? market}) {
    throw UnimplementedError();
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) {
    throw UnimplementedError();
  }
}

/// Boots the manual-add sheet inside a throwaway scaffold and surfaces
/// the [LocalSecurityChoice] returned via `Navigator.pop` so tests can
/// assert on it without driving a real route stack.
Future<LocalSecurityChoice?> _openSheet(
  WidgetTester tester, {
  required _ConfigurableMarket market,
  String prefillSymbol = 'AAPL',
}) async {
  LocalSecurityChoice? captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketDataServiceProvider.overrideWith((_) async => market),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showModalBottomSheet<LocalSecurityChoice>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) =>
                        ManualSecuritySheet(prefillSymbol: prefillSymbol),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets('"从网络导入" populates fields from a single search hit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final market = _ConfigurableMarket(
      searchResults: const [
        SymbolInfo(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          market: AssetMarket.usStock,
          currency: 'USD',
          exchange: 'NASDAQ',
        ),
      ],
    );

    await _openSheet(tester, market: market);

    expect(find.byKey(const Key('manual-security-import')), findsOneWidget);
    await tester.tap(find.byKey(const Key('manual-security-import')));
    await tester.pumpAndSettle();

    expect(market.searchCalls, 1);
    expect(market.lastQuery, 'AAPL');
    expect(market.lastMarketHint, AssetMarket.usStock);

    // Name field auto-filled from the search hit. The currency picker
    // already defaults to USD for US stocks, so we focus on the field
    // the import path actually changes.
    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('manual-security-name')),
    );
    expect(nameField.controller!.text, 'Apple Inc.');
    expect(find.text('已从网络导入元数据'), findsOneWidget);
  });

  testWidgets('"从网络导入" lets the user pick from multiple candidates',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final market = _ConfigurableMarket(
      searchResults: const [
        SymbolInfo(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          market: AssetMarket.usStock,
          currency: 'USD',
          exchange: 'NASDAQ',
        ),
        SymbolInfo(
          symbol: 'AAPL',
          name: 'Apple (other listing)',
          market: AssetMarket.usStock,
          currency: 'USD',
          exchange: 'BATS',
        ),
      ],
    );

    await _openSheet(tester, market: market);
    await tester.tap(find.byKey(const Key('manual-security-import')));
    await tester.pumpAndSettle();

    // Dialog with both candidates is rendered. Match by `key` (rather
    // than by the rendered subtitle text) since the test font may shape
    // the punctuation differently and ellipsis may truncate the rendered
    // string under narrow widths.
    expect(find.text('选择匹配项'), findsOneWidget);
    expect(find.textContaining('Apple Inc.'), findsOneWidget);
    expect(find.textContaining('Apple (other listing)'), findsOneWidget);

    await tester.tap(find.textContaining('Apple (other listing)'));
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('manual-security-name')),
    );
    expect(nameField.controller!.text, 'Apple (other listing)');
  });

  testWidgets(
      '"从网络导入" failure shows offline message and never blocks the save',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final market = _ConfigurableMarket(
      searchError:
          const NoMarketDataAvailableException('every provider failed'),
    );

    LocalSecurityChoice? choice;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          marketDataServiceProvider.overrideWith((_) async => market),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    choice = await showModalBottomSheet<LocalSecurityChoice>(
                      context: ctx,
                      isScrollControlled: true,
                      builder: (_) =>
                          const ManualSecuritySheet(prefillSymbol: 'AAPL'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('manual-security-import')));
    await tester.pumpAndSettle();

    // Failure surfaces as the FIR-78 friendly message — never a "搜索失败"
    // / raw exception toast.
    expect(find.text('网络不可用，请使用手动输入'), findsOneWidget);
    expect(find.textContaining('搜索失败'), findsNothing);

    // The form must still save without ever having reached the network.
    await tester.tap(find.byKey(const Key('manual-security-submit')));
    await tester.pumpAndSettle();
    expect(choice, isNotNull);
    expect(choice!.symbol, 'AAPL');
    expect(choice!.fromCatalog, isFalse);
  });

  testWidgets(
      'empty result set shows "未找到匹配项" without faking a successful import',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final market = _ConfigurableMarket(searchResults: const []);
    await _openSheet(tester, market: market);
    await tester.tap(find.byKey(const Key('manual-security-import')));
    await tester.pumpAndSettle();

    expect(find.text('未找到匹配项，请使用手动输入'), findsOneWidget);
  });
}
