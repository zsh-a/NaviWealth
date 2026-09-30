import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/providers.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';
import 'package:naviwealth/features/health/ui/body_measurement_entry_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

class _DelayedRepository extends HealthMetricRepository {
  _DelayedRepository({required super.db, required super.outbox});
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<void> upsert(HealthMetric metric) async {
    writes++;
    await gate?.future;
    await super.upsert(metric);
  }
}

void main() {
  testWidgets(
    'measurement waits for commit, keeps failed input and retries once',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = _DelayedRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            healthMetricRepositoryProvider.overrideWith(
              (_) async => repository,
            ),
            mutationStamperProvider.overrideWith(
              (_) async => makeStubStamper(userId: 'user'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) =>
                FTheme(data: FTheme.neutral.light.desktop, child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: FButton(
                  onPress: () => showBodyMeasurementEntrySheet(
                    context: context,
                    initialKind: HealthMetricKind.weight,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, '72.5');
      repository.gate = Completer<void>();
      await tester.tap(find.text('Save'));
      await _pump(tester);
      expect(repository.writes, 1);
      expect(
        tester.widget<EditableText>(find.byType(EditableText).first).readOnly,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await _pump(tester);
      expect(find.byType(BodyMeasurementEntrySheet), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
      repository.gate!.completeError(StateError('private path'));
      await _pump(tester);
      expect(find.text('72.5'), findsOneWidget);
      expect(find.byType(AppStatusBanner), findsOneWidget);
      expect(find.textContaining('private path'), findsNothing);
      repository.gate = null;
      await tester.tap(find.text('Save'));
      await _pump(tester);
      expect(repository.writes, 2);
      expect(find.byType(BodyMeasurementEntrySheet), findsNothing);
      expect(
        (await repository.listByKind(
          ownerUserId: 'user',
          kind: HealthMetricKind.weight,
        )).single.value,
        72.5,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}
