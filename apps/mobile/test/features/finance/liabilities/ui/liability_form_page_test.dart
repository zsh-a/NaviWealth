import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/liabilities/data/liability_repository.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/liabilities/ui/liability_form_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

class _IdentityFx implements FxRateSource {
  const _IdentityFx();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) => Decimal.one;
}

class _ControlledOutbox implements OutboxStore {
  final firstWrite = Completer<void>();
  int calls = 0;

  @override
  Future<int> depth() async => calls;

  @override
  Future<void> enqueue({required String table, required String rowId}) {
    calls += 1;
    return calls == 1 ? firstWrite.future : Future<void>.value();
  }
}

Finder _field(String label) {
  final field = find.ancestor(
    of: find.text('$label *', findRichText: true),
    matching: find.byType(FTextFormField),
  );
  return find.descendant(of: field, matching: find.byType(EditableText));
}

Future<Widget> _wrapCreatePage() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      locale: const Locale('en', 'US'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppMessenger.init(
        child: FTheme(data: FThemes.slate.light.desktop, child: child!),
      ),
      home: const LiabilityFormPage(),
    ),
  );
}

void main() {
  testWidgets('schedule details expose state and reveal hidden day errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _wrapCreatePage());
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('liability-details-toggle-label'));
    final details = find.byKey(const Key('liability-details-fields'));
    expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);
    expect(tester.widget<Offstage>(details).offstage, isTrue);
    expect(find.text('Rate type, start date & repayment'), findsOneWidget);
    expect(find.text('Name *', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Mortgage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit card').last);
    await tester.pumpAndSettle();
    expect(find.text('Billing dates & note'), findsOneWidget);

    await tester.tap(find.text('Schedule details'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(toggle).properties.expanded, isTrue);
    expect(tester.widget<Offstage>(details).offstage, isFalse);
    await tester.enterText(
      find.byKey(const Key('liability-statement-day-field')),
      '32',
    );

    await tester.tap(find.text('Schedule details'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    expect(tester.widget<Semantics>(toggle).properties.expanded, isTrue);
    expect(find.text('Must be 1–31'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed create remains editable and retries after pending write unlocks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = _ControlledOutbox();
      final stamper = makeStubStamper();
      final repo = LiabilityRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        journalEntryRepo: JournalEntryRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
          fxRateSource: const _IdentityFx(),
          baseCurrency: 'CNY',
        ),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(path: '/new', builder: (_, _) => const LiabilityFormPage()),
          GoRoute(
            path: FinanceRoutes.wealthLiabilities,
            builder: (_, _) => const Text('Liabilities destination'),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            liabilityRepositoryProvider.overrideWith((_) async => repo),
          ],
          child: MaterialApp.router(
            locale: const Locale('en', 'US'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) => AppMessenger.init(
              child: FTheme(data: FThemes.slate.light.desktop, child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(_field('Name'), 'Draft mortgage');
      await tester.enterText(_field('Principal'), '120000');
      await tester.enterText(_field('Annual rate (%)'), '4.8');
      await tester.enterText(_field('Term (months)'), '12');
      await tester.tap(find.widgetWithText(FButton, 'Save'));
      await tester.pump();

      expect(outbox.calls, 1);
      expect(find.byType(LiabilityFormPage), findsOneWidget);
      expect(
        tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
        isNull,
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(LiabilityFormPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('app.back')));
      await tester.pump();
      expect(find.byType(LiabilityFormPage), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/new');

      outbox.firstWrite.completeError(StateError('write failed'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(LiabilityFormPage), findsOneWidget);
      expect(find.text('Draft mortgage'), findsOneWidget);
      expect(
        find.text("Couldn't save your changes. Try again."),
        findsOneWidget,
      );
      expect(
        tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
        isNotNull,
      );

      await tester.tap(find.widgetWithText(FButton, 'Save'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(outbox.calls, greaterThan(1));
      expect(find.byType(LiabilityFormPage), findsNothing);
      expect(find.text('Liabilities destination'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
