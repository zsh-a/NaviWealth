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
              home: Scaffold(
                body: AssetSummaryCard(
                  asset: Asset(
                    id: 'custom:AAPL',
                    type: AssetType.stock,
                    symbol: 'AAPL',
                    currency: 'USD',
                    name: 'Apple Inc.',
                    sync: _meta(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('Apple Inc.'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
      expect(find.text('Latest close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev-test',
  hlc: Hlc.zero('dev-test'),
);
