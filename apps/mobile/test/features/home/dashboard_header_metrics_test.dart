import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/domain/transaction.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/home/home_page.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/holding_price_source.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/investment/domain/returns/returns_service.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Decimal _d(String s) => Decimal.parse(s);
DateTime _day(int y, int m, int dd) => DateTime.utc(y, m, dd);

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: _day(2026, 4, 1),
      updatedByDevice: 't',
      hlc: Hlc.zero('t'),
    );

Asset _cash(String id, String price, [String currency = 'CNY']) => Asset(
      id: id,
      type: AssetType.cash,
      symbol: id,
      currency: currency,
      lastPrice: _d(price),
      sync: _meta(),
    );

Liability _liab(String id, String principal) => Liability(
      id: id,
      type: LiabilityType.mortgage,
      name: id,
      principal: _d(principal),
      interestRate: _d('0.045'),
      currency: 'CNY',
      sync: _meta(),
    );

class _StubReturnsTxRepo implements ReturnsTransactionsRepository {
  const _StubReturnsTxRepo();
  @override
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

class _StubReturnsLotsSource implements ReturnsLotsSource {
  const _StubReturnsLotsSource();
  @override
  Future<List<Lot>> lotsAt({
    required String ownerUserId,
    required DateTime asOf,
  }) async => const [];
}

ReturnsService _stubReturnsService() {
  return ReturnsService(
    ownerUserId: 'u',
    baseCurrency: 'CNY',
    transactions: const _StubReturnsTxRepo(),
    lots: const _StubReturnsLotsSource(),
    prices: InMemoryHoldingPriceSource(const []),
    converter: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
  );
}

ProviderScope _wrap({
  required Widget child,
  required SharedPreferences prefs,
  List<Asset> manualAssets = const [],
  List<PhysicalAsset> physicalAssets = const [],
  List<Liability> liabilities = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      manualAssetsStreamProvider.overrideWith(
        (ref) => Stream.value(manualAssets),
      ),
      physicalAssetsListProvider.overrideWith(
        (ref) => Stream.value(physicalAssets),
      ),
      liabilitiesStreamProvider.overrideWith(
        (ref) => Stream.value(liabilities),
      ),
      fxRatesStreamProvider.overrideWith(
        (ref) => Stream<List<FxRate>>.value(const []),
      ),
      returnsServiceProvider.overrideWith((ref) async => _stubReturnsService()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'header shows Today / MTD / YTD cells once metrics resolve with data',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap(
      prefs: prefs,
      manualAssets: [_cash('cash', '12345')],
      child: const HomePage(),
    ));
    await tester.pumpAndSettle();

    // Three localized cell labels are rendered next to the hero number.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('MTD'), findsOneWidget);
    expect(find.text('YTD'), findsOneWidget);

    // The chip variant is used for the MTD percentage cell.
    expect(find.byType(DeltaChip), findsOneWidget);
    // Two DeltaText spans: the today currency value + YTD percentage.
    // (DeltaChip embeds a DeltaText internally — counted once via byType.)
    expect(find.byType(DeltaText), findsNWidgets(3));
  });

  testWidgets(
      'header omits the metrics row when no assets / liabilities exist',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester
        .pumpWidget(_wrap(prefs: prefs, child: const HomePage()));
    await tester.pumpAndSettle();

    // Empty snapshot — no Today/MTD/YTD strip.
    expect(find.text('Today'), findsNothing);
    expect(find.text('MTD'), findsNothing);
    expect(find.text('YTD'), findsNothing);
  });

  testWidgets('flat single-currency portfolio yields zero deltas',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(_wrap(
      prefs: prefs,
      manualAssets: [_cash('cash', '50000')],
      liabilities: [_liab('mortgage', '10000')],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context, listen: false);
        return const HomePage();
      }),
    ));
    await tester.pumpAndSettle();

    final metrics =
        container.read(dashboardHeaderMetricsProvider).requireValue;
    // The dashboard trend builder holds cash flat across history; daily and
    // MTD deltas are zero — the strip still renders with neutral arrows.
    // YTD reads from `ReturnsService.portfolioXirr`; an empty transaction
    // log resolves to `XirrFallbackAbsolute`, which the provider exposes
    // as null so the UI renders `—`.
    expect(metrics.dailyChange.amount, Decimal.zero);
    expect(metrics.monthlyChangePct, 0.0);
    expect(metrics.ytdChangePct, isNull);
  });

  testWidgets('empty portfolio collapses denominators to null pcts',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(_wrap(
      prefs: prefs,
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context, listen: false);
        return const HomePage();
      }),
    ));
    await tester.pumpAndSettle();

    final metrics =
        container.read(dashboardHeaderMetricsProvider).requireValue;
    expect(metrics.dailyChange.amount, Decimal.zero);
    expect(metrics.monthlyChangePct, isNull);
    expect(metrics.ytdChangePct, isNull);
  });
}
