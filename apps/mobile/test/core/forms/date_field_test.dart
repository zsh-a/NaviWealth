import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/date_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(
  DateTime? value, {
  bool includeTime = false,
  double textScale = 1,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: FTheme(
        data: FTheme.neutral.light.desktop,
        child: Scaffold(
          body: Form(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: DateField(
              label: 'Date',
              initialValue: value,
              required: true,
              includeTime: includeTime,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('updates initial value without dirtying the form during build', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(DateTime.utc(2026, 1, 1)));
    await tester.pumpWidget(_wrap(DateTime.utc(2026, 1, 2)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('1/2/2026'), findsOneWidget);
  });

  testWidgets('can render date and time values for transaction records', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(DateTime(2026, 1, 2, 9, 30), includeTime: true),
    );
    await tester.pump();

    expect(find.text('1/2/2026'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
  });

  testWidgets('uses separate Forui date and time fields for date-time values', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(DateTime(2026, 1, 2, 9, 30), includeTime: true),
    );

    expect(find.byWidgetPredicate((w) => w is FDateField), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is FTimeField), findsOneWidget);
  });

  testWidgets('keeps date and time compact at the default text scale', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      _wrap(DateTime(2026, 1, 2, 9, 30), includeTime: true),
    );

    final dateRect = tester.getRect(
      find.byKey(const Key('date-time-field-date')),
    );
    final timeRect = tester.getRect(
      find.byKey(const Key('date-time-field-time')),
    );
    expect(timeRect.top, dateRect.top);
    expect(timeRect.left, greaterThan(dateRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacks date and time at 2x text scale', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      _wrap(DateTime(2026, 1, 2, 9, 30), includeTime: true, textScale: 2),
    );
    await tester.pump();

    final dateRect = tester.getRect(
      find.byKey(const Key('date-time-field-date')),
    );
    final timeRect = tester.getRect(
      find.byKey(const Key('date-time-field-time')),
    );
    expect(timeRect.top, greaterThan(dateRect.bottom));
    expect(dateRect.width, 390);
    expect(timeRect.width, 390);
    expect(find.text('1/2/2026'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
