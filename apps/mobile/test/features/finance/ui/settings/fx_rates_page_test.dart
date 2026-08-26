import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_coordinator.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/ui/settings/fx_rates_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('groups historical rates into an overview and pair chart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.settings.base_currency': 'CNY',
    });
    final prefs = await SharedPreferences.getInstance();
    final rates = [
      FxRate(
        base: 'USD',
        quote: 'CNY',
        date: DateTime.utc(2026, 4, 27),
        rate: Decimal.parse('7.18'),
        source: 'yfinance',
        fetchedAt: DateTime.utc(2026, 4, 27, 8),
      ),
      FxRate(
        base: 'USD',
        quote: 'CNY',
        date: DateTime.utc(2026, 4, 28),
        rate: Decimal.parse('7.20'),
        source: 'yfinance',
        fetchedAt: DateTime.utc(2026, 4, 28, 8),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fxRatesStreamProvider.overrideWith((ref) => Stream.value(rates)),
          priceSyncStatusEventStreamProvider.overrideWith(
            (ref) => Stream.value(
              PriceSyncStatusEvent(
                status: PriceSyncStatus.fresh,
                at: DateTime.utc(2026, 4, 28, 8),
                lastSuccessAt: DateTime.utc(2026, 4, 28, 8),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const FxRatesPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Currency monitor'), findsOneWidget);
    expect(find.text('USD / CNY'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('1 USD = 7.2 CNY'), findsOneWidget);
  });
}
