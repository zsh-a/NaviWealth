import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/providers.dart';
import 'package:naviwealth/features/health/ui/health_source_attention.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

final _statusProvider = NotifierProvider<_Status, GarminSyncState>(_Status.new);

class _Status extends Notifier<GarminSyncState> {
  @override
  GarminSyncState build() => GarminConnected(
    lastSyncAt: DateTime.now().toUtc(),
    totalMetrics: 12,
    lastErrorCode: 'endpoint_unavailable',
  );
  void complete() => state = GarminConnected(
    lastSyncAt: DateTime.now().toUtc(),
    totalMetrics: 12,
  );
}

void main() {
  testWidgets(
    'automatic recovery clears the current warning without manual refresh',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            garminSyncControllerProvider.overrideWithBuild(
              (ref, _) => ref.watch(_statusProvider),
            ),
            healthSyncStatusProvider.overrideWithValue(null),
            healthSourceDataSummaryProvider.overrideWith(
              (_) async => HealthSourceDataSummary(
                garminLatestAt: DateTime.now().toUtc(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FTheme(
              data: FTheme.neutral.light.desktop,
              child: const HealthSourceAttention(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 data source failed to refresh'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HealthSourceAttention)),
      );
      container.read(_statusProvider.notifier).complete();
      await tester.pumpAndSettle();
      expect(find.byType(AppStatusBanner), findsNothing);
    },
  );
}
