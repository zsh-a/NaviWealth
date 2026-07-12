import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_summary_card.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets(
    'asset summary presents compact quote identity without overflow',
    (tester) async {
      await _pumpCard(
        tester,
        Asset(
          id: 'custom:AAPL',
          type: AssetType.stock,
          symbol: 'AAPL',
          currency: 'USD',
          name: 'Apple Inc.',
          sync: _meta(),
        ),
      );

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('Apple Inc.'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
      expect(find.text('Latest close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long security identity stays bounded at larger text scale', (
    tester,
  ) async {
    const symbol = 'VERY-LONG-SECURITY-SYMBOL';
    const name =
        'A deliberately long localized security name that must remain bounded';
    await _pumpCard(
      tester,
      Asset(
        id: 'custom:long',
        type: AssetType.etf,
        symbol: symbol,
        currency: 'USD',
        name: name,
        sync: _meta(),
      ),
      textScale: 1.5,
    );

    expect(find.text(symbol), findsOneWidget);
    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpCard(
  WidgetTester tester,
  Asset asset, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: FTheme(
        data: FThemes.slate.light.desktop,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: AssetSummaryCard(asset: asset)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev-test',
  hlc: Hlc.zero('dev-test'),
);
