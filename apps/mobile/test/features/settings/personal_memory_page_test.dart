import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/contracts/context_evidence.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_fact.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_store.dart';
import 'package:naviwealth/core/lifeos/personal_profile/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/ai/personal_memory_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

Future<PersonalProfileStore> _pumpPage(
  WidgetTester tester, {
  Future<String> Function()? currentUser,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = makeTestDatabase();
  addTearDown(db.close);
  final store = SqlitePersonalProfileStore(db);
  final now = DateTime.now().toUtc();
  await store.create(
    PersonalProfileFact(
      id: 'health-sleep-goal',
      ownerUserId: 'user-1',
      kind: PersonalProfileFactKind.goal,
      key: 'sleep_hours',
      value: 8,
      summary: 'Sleep eight hours.',
      domainScope: 'health',
      authority: EvidenceAuthority.userConfirmed,
      provenance: EvidenceProvenance(
        source: 'settings_profile',
        observedAt: now,
      ),
      confidence: 1,
      confirmedAt: now,
      validFrom: now,
      createdAt: now,
      updatedAt: now,
    ),
  );
  final theme = resolveAppTheme(
    const ThemeInputs(
      brightness: Brightness.light,
      marketMode: MarketColorMode.redUpGreenDown,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(
          currentUser ?? () async => 'user-1',
        ),
        personalProfileStoreProvider.overrideWith((ref) async => store),
        activePersonalProfileDomainScopesProvider.overrideWith(
          (ref) => const <String>{'finance'},
        ),
      ],
      child: AppThemeScope(
        data: theme,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => FTheme(
            data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
            child: child!,
          ),
          home: const PersonalMemoryPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Finder _field(int index) => find.byType(EditableText).at(index);

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

void main() {
  testWidgets('shows current facts and marks inactive-domain facts', (
    tester,
  ) async {
    await _pumpPage(tester);

    expect(find.text('Personal memory'), findsOneWidget);
    expect(find.text('Sleep eight hours.'), findsOneWidget);
    expect(
      find.textContaining('Kept locally; excluded from AI'),
      findsOneWidget,
    );
    expect(find.text('Add profile fact'), findsOneWidget);
  });

  testWidgets('dirty cancel asks before discarding and preserves the draft', (
    tester,
  ) async {
    await _pumpPage(tester);
    await _tap(tester, find.text('Add profile fact'));
    await tester.enterText(_field(0), 'cash_buffer');
    await _tap(tester, find.text('Cancel'));
    expect(find.text('Discard changes?'), findsOneWidget);
    await _tap(tester, find.text('Keep editing'));
    expect(
      tester.widget<EditableText>(_field(0)).controller.text,
      'cash_buffer',
    );
    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.text('Discard'));
    expect(find.byType(AppSheet), findsNothing);
  });

  testWidgets('reverting text and type changes restores a clean editor', (
    tester,
  ) async {
    await _pumpPage(tester);
    await _tap(tester, find.text('Sleep eight hours.'));
    expect(
      tester.widget<AppSheetFooter>(find.byType(AppSheetFooter)).enabled,
      isFalse,
    );
    await tester.enterText(_field(2), 'Draft summary');
    await tester.enterText(_field(2), 'Sleep eight hours.');
    final choice = tester.widget<AppAdaptiveChoice<PersonalProfileFactKind>>(
      find.byType(AppAdaptiveChoice<PersonalProfileFactKind>),
    );
    choice.onChanged!(PersonalProfileFactKind.preference);
    await tester.pump();
    expect(
      tester.widget<AppSheetFooter>(find.byType(AppSheetFooter)).enabled,
      isTrue,
    );
    tester
        .widget<AppAdaptiveChoice<PersonalProfileFactKind>>(
          find.byType(AppAdaptiveChoice<PersonalProfileFactKind>),
        )
        .onChanged!(PersonalProfileFactKind.goal);
    await tester.pump();
    expect(
      tester.widget<AppSheetFooter>(find.byType(AppSheetFooter)).enabled,
      isFalse,
    );
    await _tap(tester, find.text('Cancel'));
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(AppSheet), findsNothing);
  });

  testWidgets('saving blocks duplicate submits and every dismissal path', (
    tester,
  ) async {
    final owner = Completer<String>();
    var requests = 0;
    final store = await _pumpPage(
      tester,
      currentUser: () {
        requests++;
        return requests == 1 ? Future.value('user-1') : owner.future;
      },
    );
    await _tap(tester, find.text('Sleep eight hours.'));
    await tester.enterText(_field(2), 'Sleep nine hours.');
    await _tap(tester, find.text('Save'), settle: false);
    final footer = tester.widget<AppSheetFooter>(find.byType(AppSheetFooter));
    expect(footer.busy, isTrue);
    footer.onSubmit();
    await tester.pump();
    expect(requests, 2);
    for (final field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(field.readOnly, isTrue);
    }
    expect(
      tester
          .widget<AppAdaptiveChoice<PersonalProfileFactKind>>(
            find.byType(AppAdaptiveChoice<PersonalProfileFactKind>),
          )
          .onChanged,
      isNull,
    );
    await _tap(tester, find.text('Cancel'), settle: false);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.dragFrom(
      tester.getTopLeft(find.byType(AppSheet)) + const Offset(195, 15),
      const Offset(0, 600),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);

    owner.complete('user-1');
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsNothing);
    expect(find.text('Sleep nine hours.'), findsOneWidget);
    final facts = await store.listCurrent(
      ownerUserId: 'user-1',
      at: DateTime.now().toUtc(),
    );
    expect(facts, hasLength(1));
    expect(facts.single.supersedesFactId, 'health-sleep-goal');
  });

  testWidgets('failed save keeps input and allows retry after correcting it', (
    tester,
  ) async {
    final store = await _pumpPage(tester);
    await _tap(tester, find.text('Add profile fact'));
    await tester.enterText(_field(0), 'sleep_hours');
    await tester.enterText(_field(2), 'Sleep nine hours.');
    await tester.enterText(_field(3), 'health');
    await _tap(tester, find.text('Save'));
    expect(find.text("Couldn't save your changes. Try again."), findsOneWidget);
    expect(
      tester.widget<EditableText>(_field(2)).controller.text,
      'Sleep nine hours.',
    );
    expect(
      tester.widget<AppSheetFooter>(find.byType(AppSheetFooter)).busy,
      isFalse,
    );
    await tester.enterText(_field(0), 'sleep_target');
    await _tap(tester, find.text('Save'));
    expect(find.byType(AppSheet), findsNothing);
    final facts = await store.listCurrent(
      ownerUserId: 'user-1',
      at: DateTime.now().toUtc(),
    );
    expect(facts, hasLength(2));
    expect(facts.any((fact) => fact.key == 'sleep_target'), isTrue);
  });

  testWidgets(
    'delete is a separate labeled 48px action and keeps confirmation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final store = await _pumpPage(tester);
      final delete = find.bySemanticsLabel('Delete');
      expect(tester.getSize(delete), const Size(48, 48));
      final node = tester.getSemantics(delete);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.text('Forget this profile fact?'), findsOneWidget);
      expect(find.text('Edit profile fact'), findsNothing);
      await _tap(tester, find.text('Cancel'));
      expect(find.text('Sleep eight hours.'), findsOneWidget);
      await _tap(tester, find.byIcon(FLucideIcons.trash2));
      await _tap(tester, find.text('Delete'));
      expect(
        await store.listCurrent(
          ownerUserId: 'user-1',
          at: DateTime.now().toUtc(),
        ),
        isEmpty,
      );
      expect(find.text('Sleep eight hours.'), findsNothing);
      semantics.dispose();
    },
  );
}
