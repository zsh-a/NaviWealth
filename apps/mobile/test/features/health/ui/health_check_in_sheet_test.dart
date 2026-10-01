import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/health_check_in_providers.dart';
import 'package:naviwealth/features/health/data/health_check_in_repository.dart';
import 'package:naviwealth/features/health/domain/health_check_in.dart';
import 'package:naviwealth/features/health/ui/health_check_in_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

final _day = DateTime(2026, 10, 1);

class _DelayedRepository extends HealthCheckInRepository {
  _DelayedRepository({
    required super.db,
    required super.outbox,
    required super.stamper,
  }) : super(clock: () => _day);
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<HealthCheckIn> save({
    required DateTime day,
    int? energy,
    int? sleepQuality,
    int? stress,
    List<String> tags = const [],
    String? note,
    String? expectedOwnerUserId,
  }) async {
    writes++;
    await gate?.future;
    return super.save(
      day: day,
      energy: energy,
      sleepQuality: sleepQuality,
      stress: stress,
      tags: tags,
      note: note,
      expectedOwnerUserId: expectedOwnerUserId,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  HealthCheckInRepository repository, {
  double width = 800,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(() async => 'user'),
        healthCheckInRepositoryProvider.overrideWith((_) async => repository),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: FTheme(
            data: buildAppForuiTheme(brightness: brightness, touch: true),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FButton(
              onPress: () =>
                  showHealthCheckInSheet(context: context, day: _day),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'optional ratings and events save, reload, edit and delete a single date',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = HealthCheckInRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(userId: 'user'),
        clock: () => _day,
      );
      await _pump(tester, repo);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Record at least one feeling, event, or note.'),
        findsOneWidget,
      );
      await tester.tap(find.text('4').first);
      await tester.tap(find.text('Caffeine'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final entry = (await repo.findDay(ownerUserId: 'user', day: _day))!;
      expect(entry.energy, 4);
      expect(entry.sleepQuality, isNull);
      expect(entry.tags, ['caffeine']);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').first);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        (await repo.findDay(ownerUserId: 'user', day: _day))!.id,
        entry.id,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete check-in'));
      await tester.tap(find.text('Delete check-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(await repo.findDay(ownerUserId: 'user', day: _day), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'failed saves retain input, lock controls and retry without duplicate writes',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = _DelayedRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(userId: 'user'),
      );
      await _pump(tester, repo);
      await tester.tap(find.text('4').first);
      await tester.tap(find.text('Add a note (optional)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Tired after travel');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      repo.gate = Completer<void>();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).readOnly,
        true,
      );
      expect(
        tester
            .widget<SegmentedRow<int?>>(find.byType(SegmentedRow<int?>).first)
            .onChanged,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(HealthCheckInSheet), findsOneWidget);
      repo.gate!.completeError(StateError('private health content'));
      await tester.pumpAndSettle();
      expect(find.text('Tired after travel'), findsOneWidget);
      expect(find.byType(AppStatusBanner), findsOneWidget);
      expect(find.textContaining('private health content'), findsNothing);
      repo.gate = null;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.writes, 2);
      expect((await db.select(db.healthCheckIns).get()).length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('320px large Chinese text works in ${brightness.name} mode', (
      tester,
    ) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = HealthCheckInRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(userId: 'user'),
        clock: () => _day,
      );
      await _pump(
        tester,
        repo,
        width: 320,
        scale: 2,
        brightness: brightness,
        locale: const Locale('zh'),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('睡前看屏幕'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('睡前看屏幕'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
