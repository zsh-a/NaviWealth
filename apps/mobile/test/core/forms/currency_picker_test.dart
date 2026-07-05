import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/currency_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders a stored currency outside the common list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(CurrencyPicker(value: 'CHF', onChanged: (_) {})),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('CHF · CHF'), findsOneWidget);
  });

  testWidgets('treats an empty stored currency as unselected', (tester) async {
    await tester.pumpWidget(
      _wrap(CurrencyPicker(value: '', onChanged: (_) {})),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('CHF · CHF'), findsNothing);
  });
}
