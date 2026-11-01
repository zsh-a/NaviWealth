import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/health_calendar_providers.dart';
import 'package:naviwealth/features/health/data/health_meal_providers.dart';
import 'package:naviwealth/features/health/data/health_meal_repository.dart';
import 'package:naviwealth/features/health/data/meal_food_catalog.dart';
import 'package:naviwealth/features/health/domain/health_meal.dart';
import 'package:naviwealth/features/health/ui/meal_date_control.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../../support/test_app_theme.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

final _now = DateTime(2026, 10, 28, 12);

class _CalendarRepository extends HealthMealRepository {
  _CalendarRepository({
    required super.db,
    required super.outbox,
    required super.stamper,
    required super.clock,
  });

  bool failCoverage = false;
  final initialMeals = <HealthMeal>[];

  @override
  Stream<Map<DateTime, int>> watchRecordedDayCounts({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) => failCoverage
      ? Stream.error(StateError('calendar unavailable'))
      : super.watchRecordedDayCounts(
          ownerUserId: ownerUserId,
          from: from,
          to: to,
        );
}

Future<_CalendarRepository> _pump(
  WidgetTester tester, {
  DateTime? initial,
  bool browse = false,
  double width = 390,
  double scale = 1,
  Locale locale = const Locale('en'),
  DateTime Function()? clock,
  ValueChanged<DateTime>? onChange,
  Map<DateTime, int> recordedDays = const {},
  bool failCoverage = false,
  Brightness brightness = Brightness.light,
  bool highContrast = false,
}) async {
  final db = makeTestDatabase();
  addTearDown(db.close);
  await DomainOptInStore(db).write(DomainOptIns(const {DomainScope.health}));
  final repository = _CalendarRepository(
    db: db,
    outbox: InMemoryOutboxStore(),
    stamper: makeStubStamper(userId: 'meal-calendar-owner'),
    clock: clock ?? () => _now,
  )..failCoverage = failCoverage;
  for (final entry in recordedDays.entries) {
    for (var i = 0; i < entry.value; i++) {
      repository.initialMeals.add(
        await repository.save(
          expectedOwnerUserId: 'meal-calendar-owner',
          capturedAt: (clock ?? () => _now)(),
          day: entry.key,
          type: HealthMealType.lunch,
          foods: [mealFoodCatalog.first.portion(100)],
        ),
      );
    }
  }
  tester.view
    ..physicalSize = Size(width, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var selected = initial ?? DateTime.utc(2026, 10, 28);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        healthClockProvider.overrideWithValue(clock ?? () => _now),
        appDatabaseProvider.overrideWith((_) async => db),
        auth.authStateProvider.overrideWithValue(const AuthLocalOnly()),
        currentUserIdProvider.overrideWithValue(
          () async => 'meal-calendar-owner',
        ),
        activeUserIdProvider.overrideWithValue('meal-calendar-owner'),
        healthMealRepositoryProvider.overrideWith((_) async => repository),
      ],
      child: AppThemeScope(
        data: resolveAppTheme(
          ThemeInputs(
            brightness: brightness,
            marketMode: MarketColorMode.redUpGreenDown,
            highContrast: highContrast,
          ),
        ),
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? AppTheme.light(highContrast: highContrast)
              : AppTheme.dark(highContrast: highContrast),
          locale: locale,
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            ...FLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
              highContrast: highContrast,
            ),
            child: highContrast
                ? FTheme(
                    data: buildAppForuiTheme(
                      brightness: brightness,
                      highContrast: true,
                      touch: true,
                    ),
                    child: child!,
                  )
                : buildTestAppTheme(context, child),
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Consumer(
                builder: (context, ref, _) => StatefulBuilder(
                  builder: (context, setState) => MealDateControl(
                    day: selected,
                    today: ref.watch(healthCalendarDayProvider),
                    browse: browse,
                    onChanged: (day) {
                      setState(() => selected = day);
                      onChange?.call(day);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return repository;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 1));
}

void _testCalendar(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}

void main() {
  setUpAll(() => initializeDateFormatting());

  for (final (brightness, contrast) in [
    (Brightness.light, false),
    (Brightness.dark, false),
    (Brightness.dark, true),
  ]) {
    _testCalendar(
      'record markers remain reachable at large text: $brightness / $contrast',
      (tester) async {
        await _pump(
          tester,
          width: 320,
          scale: 2,
          locale: const Locale('zh'),
          brightness: brightness,
          highContrast: contrast,
          recordedDays: {DateTime.utc(2026, 10, 28): 1},
        );
        await tester.tap(find.byKey(const Key('meal-date-open')));
        await _settle(tester);
        final cell = find.byKey(const ValueKey('meal-date-cell-2026-10-28'));
        await tester.ensureVisible(cell);
        await _settle(tester);
        expect(
          find
              .byKey(const ValueKey('meal-date-recorded-2026-10-28'))
              .hitTestable(),
          findsOneWidget,
        );
        final cancel = find.ancestor(
          of: find.text('取消'),
          matching: find.byType(AppQuietButton),
        );
        expect(
          tester.getRect(cell).bottom,
          lessThanOrEqualTo(tester.getRect(cancel).top),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(cell);
        await _settle(tester);
        expect(find.byType(FCalendar), findsNothing);
      },
    );
  }

  _testCalendar(
    'saved days, including the selection, have markers and accessible counts',
    (tester) async {
      await _pump(
        tester,
        recordedDays: {
          DateTime.utc(2026, 10, 25): 2,
          DateTime.utc(2026, 10, 28): 1,
        },
      );
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('meal-date-recorded-2026-10-25')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('meal-date-recorded-2026-10-28')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('meal-date-recorded-2026-10-26')),
        findsNothing,
      );
      expect(find.text('2 recorded days this month'), findsOneWidget);
      final summary = tester.widget<Semantics>(
        find.byKey(const Key('meal-calendar-record-summary')),
      );
      expect(summary.properties.label, contains('Oct 25, 2026: 2 saved meals'));
      expect(summary.properties.label, contains('Oct 28, 2026: 1 saved meal'));
      await tester.tap(find.byKey(const ValueKey('meal-date-cell-2026-10-25')));
      await _settle(tester);
      expect(find.byType(FCalendar), findsNothing);
      expect(find.text('Oct 25'), findsOneWidget);
    },
  );

  _testCalendar(
    'month changes and live deletion update only the affected markers',
    (tester) async {
      final repo = await _pump(
        tester,
        recordedDays: {
          DateTime.utc(2026, 9, 17): 1,
          DateTime.utc(2026, 10, 25): 1,
        },
      );
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await _settle(tester);
      await repo.delete(
        repo.initialMeals.singleWhere(
          (meal) => meal.day == DateTime.utc(2026, 10, 25),
        ),
      );
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('meal-date-recorded-2026-10-25')),
        findsNothing,
      );
      expect(find.text('No recorded days this month'), findsOneWidget);
      await tester.tap(
        find.widgetWithIcon(AppIconButton, FLucideIcons.chevronLeft),
      );
      await _settle(tester);
      expect(find.text('September 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('meal-date-recorded-2026-9-17')),
        findsOneWidget,
      );
      expect(find.text('1 recorded day this month'), findsOneWidget);
      await tester.tap(
        find.widgetWithIcon(AppIconButton, FLucideIcons.chevronRight),
      );
      await _settle(tester);
      expect(find.text('No recorded days this month'), findsOneWidget);
    },
  );

  _testCalendar(
    'coverage failure keeps date selection available and can retry',
    (tester) async {
      final repo = await _pump(
        tester,
        failCoverage: true,
        recordedDays: {DateTime.utc(2026, 10, 25): 1},
      );
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await _settle(tester);
      expect(
        find.textContaining("Record markers couldn't load"),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('meal-date-cell-2026-10-25')));
      await _settle(tester);
      expect(find.byType(FCalendar), findsNothing);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await _settle(tester);
      repo.failCoverage = false;
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.textContaining("Record markers couldn't load"), findsNothing);
      expect(
        find.byKey(const ValueKey('meal-date-recorded-2026-10-25')),
        findsOneWidget,
      );
    },
  );

  test(
    'relative dates include absolute dates, weekdays and cross-year context',
    () {
      final l = lookupAppLocalizations(const Locale('zh'));
      final today = DateTime.utc(2026);
      final current = mealDateLabels(
        l10n: l,
        locale: const Locale('zh'),
        day: today,
        today: today,
      );
      expect(current.title, '今天');
      expect(current.detail, contains('1月1日'));
      expect(current.detail, contains('周四'));
      final yesterday = mealDateLabels(
        l10n: l,
        locale: const Locale('zh'),
        day: DateTime.utc(2025, 12, 31),
        today: today,
      );
      expect(yesterday.title, '昨天');
      expect(yesterday.detail, contains('2025'));
      final older = mealDateLabels(
        l10n: l,
        locale: const Locale('zh'),
        day: DateTime.utc(2025, 12, 30),
        today: today,
      );
      expect(older.title, contains('2025'));
      expect(older.detail, '周二');
      expect(older.full, contains('2025年12月30日'));
    },
  );

  _testCalendar(
    'day browsing handles leap days and prevents future selection',
    (tester) async {
      final changed = <DateTime>[];
      await _pump(
        tester,
        browse: true,
        initial: DateTime.utc(2024, 3),
        clock: () => DateTime(2024, 3, 1, 12),
        onChange: changed.add,
      );
      expect(
        tester
            .widget<AppIconButton>(find.byKey(const Key('meal-date-next')))
            .onPress,
        isNull,
      );
      await tester.tap(find.byKey(const Key('meal-date-previous')));
      await _settle(tester);
      expect(changed.last, DateTime.utc(2024, 2, 29));
      await tester.tap(find.byKey(const Key('meal-date-return-today')));
      await _settle(tester);
      expect(changed.last, DateTime.utc(2024, 3));
      expect(find.byKey(const Key('meal-date-return-today')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _testCalendar(
    'picker shortcuts apply immediately and cancel preserves the day',
    (tester) async {
      final changed = <DateTime>[];
      await _pump(tester, onChange: changed.add);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await _settle(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(changed, isEmpty);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('meal-date-yesterday')));
      await _settle(tester);
      expect(changed, [DateTime.utc(2026, 10, 27)]);
      expect(find.byType(FCalendar), findsNothing);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('meal-date-today')));
      await _settle(tester);
      expect(changed.last, DateTime.utc(2026, 10, 28));
    },
  );

  _testCalendar('calendar disables tomorrow and accepts a past day', (
    tester,
  ) async {
    final changed = <DateTime>[];
    await _pump(tester, onChange: changed.add);
    await tester.tap(find.byKey(const Key('meal-date-open')));
    await _settle(tester);
    final calendar = tester.widget<FCalendar>(find.byType(FCalendar));
    final control = calendar.control as FWheelCalendarControl;
    expect(control.selectable!(DateTime.utc(2026, 10, 29)), isFalse);
    expect(control.selectable!(DateTime.utc(1969, 12, 31)), isFalse);
    await tester.tap(find.text('29').hitTestable().last);
    await _settle(tester);
    expect(changed, isEmpty);
    expect(find.byType(FCalendar), findsOneWidget);
    await tester.tap(find.text('25'));
    await _settle(tester);
    expect(changed, [DateTime.utc(2026, 10, 25)]);
    expect(find.byType(FCalendar), findsNothing);
  });

  _testCalendar(
    'today and an open picker follow the calendar day across midnight',
    (tester) async {
      var now = _now;
      final changed = <DateTime>[];
      await _pump(tester, clock: () => now, onChange: changed.add);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await _settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MealDateControl)),
      );
      now = DateTime(2026, 10, 29, 0, 1);
      container.invalidate(healthCalendarDayProvider);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('meal-date-today')));
      await _settle(tester);
      expect(changed, [DateTime.utc(2026, 10, 29)]);
      expect(find.text('Today'), findsOneWidget);
    },
  );

  _testCalendar('Chinese calendar remains usable on 320px with large text', (
    tester,
  ) async {
    await _pump(tester, width: 320, scale: 2, locale: const Locale('zh'));
    await tester.tap(find.byKey(const Key('meal-date-open')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('25日'), findsNothing);
    final sunday = find
        .byKey(const ValueKey('meal-date-cell-2026-10-25'))
        .hitTestable();
    expect(sunday, findsOneWidget);
    expect(tester.getRect(sunday).right, lessThanOrEqualTo(304));
    await tester.ensureVisible(find.byKey(const Key('meal-calendar-period')));
    await tester.tap(find.byKey(const Key('meal-calendar-period')));
    await _settle(tester);
    expect(find.byType(FPicker), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('meal-calendar-period')));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const Key('meal-date-yesterday')));
    await tester.tap(find.byKey(const Key('meal-date-yesterday')));
    await _settle(tester);
    expect(find.text('昨天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
