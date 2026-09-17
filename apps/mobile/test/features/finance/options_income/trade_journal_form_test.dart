import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/options_income/ui/trade_journal_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('journal is a full page with numeric fields and guarded back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          accountsStreamProvider.overrideWith((_) => Stream.value([])),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) =>
              FTheme(data: FTheme.neutral.light.desktop, child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTradeJournalSheet(context),
                child: const Text('Open journal'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open journal'));
    await tester.pumpAndSettle();
    expect(find.byType(AppFormPageScaffold), findsOneWidget);
    expect(find.byType(AppNumberField), findsNWidgets(6));
    await tester.enterText(find.byType(EditableText).first, 'AAPL');
    await tester.pump();
    final context = tester.element(find.byType(AppFormPageScaffold));
    final l10n = AppLocalizations.of(context);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.unsavedChangesKeepEditing));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'AAPL',
    );
    expect(tester.takeException(), isNull);
  });
}
