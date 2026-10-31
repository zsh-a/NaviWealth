import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/health/data/health_calendar_providers.dart';
import 'package:naviwealth/features/health/ui/meal_date_control.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../support/test_app_theme.dart';

final _now = DateTime(2026, 10, 28, 12);

Future<void> _pump(
  WidgetTester tester, {
  DateTime? initial,
  bool browse = false,
  double width = 390,
  double scale = 1,
  Locale locale = const Locale('en'),
  DateTime Function()? clock,
  ValueChanged<DateTime>? onChange,
}) async {
  tester.view
    ..physicalSize = Size(width, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  var selected = initial ?? DateTime.utc(2026, 10, 28);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [healthClockProvider.overrideWithValue(clock ?? () => _now)],
      child: MaterialApp(
        theme: AppTheme.light(),
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
          ),
          child: buildTestAppTheme(context, child),
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
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting());

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

  testWidgets('day browsing handles leap days and prevents future selection', (
    tester,
  ) async {
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
    await tester.pumpAndSettle();
    expect(changed.last, DateTime.utc(2024, 2, 29));
    await tester.tap(find.byKey(const Key('meal-date-return-today')));
    await tester.pumpAndSettle();
    expect(changed.last, DateTime.utc(2024, 3));
    expect(find.byKey(const Key('meal-date-return-today')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'picker shortcuts apply immediately and cancel preserves the day',
    (tester) async {
      final changed = <DateTime>[];
      await _pump(tester, onChange: changed.add);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(changed, isEmpty);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-date-yesterday')));
      await tester.pumpAndSettle();
      expect(changed, [DateTime.utc(2026, 10, 27)]);
      expect(find.byType(FCalendar), findsNothing);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-date-today')));
      await tester.pumpAndSettle();
      expect(changed.last, DateTime.utc(2026, 10, 28));
    },
  );

  testWidgets('calendar disables tomorrow and accepts a past day', (
    tester,
  ) async {
    final changed = <DateTime>[];
    await _pump(tester, onChange: changed.add);
    await tester.tap(find.byKey(const Key('meal-date-open')));
    await tester.pumpAndSettle();
    final calendar = tester.widget<FCalendar>(find.byType(FCalendar));
    final control = calendar.control as FWheelCalendarControl;
    expect(control.selectable!(DateTime.utc(2026, 10, 29)), isFalse);
    expect(control.selectable!(DateTime.utc(1969, 12, 31)), isFalse);
    await tester.tap(find.text('29').hitTestable().last);
    await tester.pumpAndSettle();
    expect(changed, isEmpty);
    expect(find.byType(FCalendar), findsOneWidget);
    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();
    expect(changed, [DateTime.utc(2026, 10, 25)]);
    expect(find.byType(FCalendar), findsNothing);
  });

  testWidgets(
    'today and an open picker follow the calendar day across midnight',
    (tester) async {
      var now = _now;
      final changed = <DateTime>[];
      await _pump(tester, clock: () => now, onChange: changed.add);
      await tester.tap(find.byKey(const Key('meal-date-open')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MealDateControl)),
      );
      now = DateTime(2026, 10, 29, 0, 1);
      container.invalidate(healthCalendarDayProvider);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-date-today')));
      await tester.pumpAndSettle();
      expect(changed, [DateTime.utc(2026, 10, 29)]);
      expect(find.text('Today'), findsOneWidget);
    },
  );

  testWidgets('Chinese calendar remains usable on 320px with large text', (
    tester,
  ) async {
    await _pump(tester, width: 320, scale: 2, locale: const Locale('zh'));
    await tester.tap(find.byKey(const Key('meal-date-open')));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(find.byType(FPicker), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('meal-calendar-period')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('meal-date-yesterday')));
    await tester.tap(find.byKey(const Key('meal-date-yesterday')));
    await tester.pumpAndSettle();
    expect(find.text('昨天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
