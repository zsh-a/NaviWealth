import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/cashflow/ui/recurring_transaction_form.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Account _account(String id, String name, AccountSide side) {
  return Account(
    id: id,
    type: AccountCategory.bank,
    name: name,
    currency: 'CNY',
    category: side,
    sync: SyncMeta(
      ownerUserId: 'user',
      updatedAt: DateTime.utc(2026),
      updatedByDevice: 'device',
      hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'device'),
    ),
  );
}

class _OpenFormHost extends ConsumerWidget {
  const _OpenFormHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FScaffold(
      child: Center(
        child: FButton(
          onPress: () => showRecurringTransactionForm(context, ref),
          child: const Text('open-recurring-form'),
        ),
      ),
    );
  }
}

Future<Widget> _wrap() async {
  SharedPreferences.setMockInitialValues(const {});
  final preferences = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      accountsStreamProvider.overrideWith(
        (_) => Stream.value([
          _account('cash', 'Wallet', AccountSide.asset),
          _account('salary', 'Salary', AccountSide.income),
          _account('dining', 'Dining', AccountSide.expense),
        ]),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppMessenger.init(child: child!),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: const _OpenFormHost(),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'keeps optional recurrence settings in an accessible disclosure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(await _wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('open-recurring-form'));
      await tester.pumpAndSettle();

      expect(find.text('Starts on *', findRichText: true), findsOneWidget);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('More options'), findsOneWidget);
      final toggle = find.byKey(const Key('recurring-details-toggle-label'));
      final fields = find.byKey(const Key('recurring-details-fields'));
      expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);
      expect(tester.widget<Offstage>(fields).offstage, isTrue);

      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();

      expect(tester.widget<Semantics>(toggle).properties.expanded, isTrue);
      expect(tester.widget<Offstage>(fields).offstage, isFalse);
      final note = find.widgetWithText(FTextFormField, 'Note');
      await tester.ensureVisible(note);
      await tester.enterText(note, 'Annual insurance renewal');

      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);
      expect(find.text('Custom options configured'), findsOneWidget);

      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: note, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Annual insurance renewal',
      );

      await tester.enterText(
        find.byKey(const Key('recurring-interval-field')),
        '0',
      );
      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);

      await tester.tap(find.widgetWithText(FButton, 'Save'));
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(toggle).properties.expanded, isTrue);
      expect(find.text('Enter a positive whole number'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
