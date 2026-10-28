import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/composition/health_route_paths.dart';
import 'package:naviwealth/features/health/data/health_meal_providers.dart';
import 'package:naviwealth/features/health/data/health_meal_repository.dart';
import 'package:naviwealth/features/health/data/health_series_providers.dart';
import 'package:naviwealth/features/health/data/meal_food_catalog.dart';
import 'package:naviwealth/features/health/data/meal_photo_capture.dart';
import 'package:naviwealth/features/health/data/meal_recognition_client.dart';
import 'package:naviwealth/features/health/domain/health_meal.dart';
import 'package:naviwealth/features/health/ui/health_meal_entry_page.dart';
import 'package:naviwealth/features/health/ui/health_meals_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../../support/test_app_theme.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

final _now = DateTime(2026, 10, 28, 12);

class _Capture extends MealPhotoCapture {
  @override
  Future<Uint8List?> pick({required bool camera}) async =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
}

class _Recognition implements MealRecognitionClient {
  @override
  String get providerLabel => 'Test Vision';
  int calls = 0;
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<MealRecognitionDraft> recognize({
    required Uint8List photoBytes,
    required String languageCode,
    required bool allowUpload,
  }) async {
    expect(allowUpload, true);
    calls++;
    await gate?.future;
    if (fail) throw StateError('private provider response');
    return MealRecognitionDraft(
      foods: [mealFoodCatalog.first.portion(200, name: 'Rice')],
      model: 'test-vision',
    );
  }
}

class _DelayedRepository extends HealthMealRepository {
  _DelayedRepository(AppDatabase db)
    : super(
        db: db,
        outbox: DriftOutboxStore(db),
        stamper: makeStubStamper(userId: kLocalOnlyUserId),
        clock: () => _now,
      );
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<HealthMeal> save({
    String? id,
    required String expectedOwnerUserId,
    expectedRevision,
    required DateTime capturedAt,
    required DateTime day,
    required HealthMealType type,
    required List<MealFood> foods,
    String? note,
    String? recognitionModel,
    Uint8List? photoBytes,
    bool removePhoto = false,
  }) async {
    writes++;
    await gate?.future;
    return super.save(
      id: id,
      expectedOwnerUserId: expectedOwnerUserId,
      expectedRevision: expectedRevision,
      capturedAt: capturedAt,
      day: day,
      type: type,
      foods: foods,
      note: note,
      recognitionModel: recognitionModel,
      photoBytes: photoBytes,
      removePhoto: removePhoto,
    );
  }
}

Future<GoRouter> _pump(
  WidgetTester tester,
  AppDatabase db, {
  _Recognition? client,
  HealthMealRepository? repository,
  double width = 800,
  double scale = 1,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await DomainOptInStore(db).write(DomainOptIns(const {DomainScope.health}));
  final router = GoRouter(
    initialLocation: HealthRoutes.meals,
    routes: [
      GoRoute(
        path: HealthRoutes.meals,
        builder: (_, _) => const HealthMealsPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const HealthMealEntryPage()),
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                HealthMealEntryPage(mealId: state.pathParameters['id']),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        auth.authStateProvider.overrideWithValue(const AuthLocalOnly()),
        outboxStoreProvider.overrideWith((_) async => DriftOutboxStore(db)),
        mutationStamperProvider.overrideWith(
          (_) async => makeStubStamper(userId: kLocalOnlyUserId),
        ),
        healthClockProvider.overrideWithValue(() => _now),
        mealPhotoCaptureProvider.overrideWithValue(_Capture()),
        mealRecognitionClientProvider.overrideWithValue(client),
        if (repository != null)
          healthMealRepositoryProvider.overrideWith((_) async => repository),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: buildTestAppTheme(context, child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(locale.languageCode == 'zh' ? '记录饮食' : 'Record a meal'),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _identify(WidgetTester tester) async {
  await tester.tap(find.text('Choose photo'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('meal-recognize')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send and identify'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'photo consent, editable estimates, confirm save, history edit and delete',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final client = _Recognition();
      await _pump(tester, db, client: client);
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-recognize')));
      await tester.pumpAndSettle();
      expect(client.calls, 0);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(client.calls, 0);
      await tester.tap(find.byKey(const Key('meal-recognize')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send and identify'));
      await tester.pumpAndSettle();
      expect(client.calls, 1);
      expect(find.text('Rice'), findsOneWidget);
      expect(await db.select(db.healthMeals).get(), isEmpty);
      await tester.ensureVisible(find.text('Edit food'));
      await tester.tap(find.text('Edit food'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('meal-food-grams')),
          matching: find.byType(EditableText),
        ),
        '100',
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
      final first = (await db.select(db.healthMeals).get()).single;
      expect(first.foodsJson, contains('100.0'));
      expect(
        (await db.select(db.healthMealPhotos).get()).single.bytes,
        isNotEmpty,
      );
      expect(find.text('About 130 kcal'), findsWidgets);
      await tester.tap(find.text('Lunch'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(
        (await db.select(db.healthMeals).get()).single.deletedAt,
        isNotNull,
      );
      expect(await db.select(db.healthMealPhotos).get(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed saves preserve food edits, block duplicate submission, and retry',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = _DelayedRepository(db);
      await _pump(tester, db, client: _Recognition(), repository: repository);
      await _identify(tester);
      repository.gate = Completer<void>();
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pump();
      expect(repository.writes, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(HealthMealEntryPage), findsOneWidget);
      repository.gate!.completeError(StateError('private meal details'));
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
      expect(find.textContaining('private meal details'), findsNothing);
      expect(find.text("Couldn't save your changes. Try again."), findsWidgets);
      repository.gate = null;
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
      expect(repository.writes, 2);
      expect((await db.select(db.healthMeals).get()).length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('manual entry works without a model and guards unsaved changes', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.text('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('meal-food-name')),
        matching: find.byType(EditableText),
      ),
      'Homemade soup',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('meal-food-kcal')),
        matching: find.byType(EditableText),
      ),
      '80',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(
      (await db.select(db.healthMeals).get()).single.foodsJson,
      contains('Homemade soup'),
    );
    expect(find.text('About 80 kcal'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('320px Chinese form with large text remains usable', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _pump(tester, db, width: 320, scale: 2, locale: const Locale('zh'));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('添加食物'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('添加食物'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'late recognition after HealthOS is disabled cannot populate or save a meal',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final client = _Recognition()..gate = Completer<void>();
      await _pump(tester, db, client: client);
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-recognize')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send and identify'));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HealthMealEntryPage)),
      );
      await container
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, false);
      client.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsNothing);
      expect(
        find.text(
          'The user or HealthOS setting changed. Reopen this meal to continue.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
      expect(await db.select(db.healthMeals).get(), isEmpty);
    },
  );
}
