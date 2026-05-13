import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/shared/forms/date_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(DateTime? value) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(
        body: Form(
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: DateField(label: 'Date', initialValue: value, required: true),
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
}
