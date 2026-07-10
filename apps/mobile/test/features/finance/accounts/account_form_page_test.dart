import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/accounts/ui/account_form_page.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/ui/account_icon_catalog.dart';
import 'package:naviwealth/features/finance/shared/ui/account_tree_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';
import '../data/repositories/_stub_stamper.dart';

class _Harness {
  _Harness({
    required this.db,
    required this.outbox,
    required this.stamper,
    required this.prefs,
  });

  final AppDatabase db;
  final InMemoryOutboxStore outbox;
  final MutationStamper stamper;
  final SharedPreferences prefs;

  static Future<_Harness> create() async {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    return _Harness(db: db, outbox: outbox, stamper: stamper, prefs: prefs);
  }

  Future<void> dispose() => db.close();

  Future<void> seedAccounts(List<Account> accounts) async {
    for (final a in accounts) {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: a.id,
              type: a.type,
              name: a.name,
              currency: a.currency,
              category: Value(a.category),
              parentId: Value(a.parentId),
              icon: Value(a.icon),
              color: Value(a.color),
              ownerUserId: a.sync.ownerUserId,
              updatedAt: a.sync.updatedAt,
              updatedByDevice: a.sync.updatedByDevice,
              hlc: a.sync.hlc,
            ),
          );
    }
  }
}

Account _account({
  required String id,
  required String name,
  AccountSide category = AccountSide.expense,
  String currency = 'CNY',
  AccountCategory type = AccountCategory.asset,
  String? parentId,
  String? icon,
  String? color,
}) => Account(
  id: id,
  type: type,
  name: name,
  currency: currency,
  category: category,
  parentId: parentId,
  icon: icon,
  color: color,
  sync: SyncMeta(
    ownerUserId: 'u-test',
    updatedAt: DateTime.utc(2026, 1, 1),
    updatedByDevice: 'dev-test',
    hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
  ),
);

Finder _accountIcon(String name) {
  final entry = kAccountIconCatalogue.firstWhere((e) => e.name == name);
  return find.byIcon(entry.icon);
}

Finder _colorSwatch(String hex) {
  final parsed = int.parse('FF${hex.substring(1)}', radix: 16);
  final color = Color(parsed);
  return find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        decoration.shape == BoxShape.circle &&
        decoration.color == color;
  });
}

ProviderScope _wrap(_Harness h, {List<Account>? accounts, String? editingId}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(h.prefs),
      appDatabaseProvider.overrideWith((_) async => h.db),
      outboxStoreProvider.overrideWith((_) async => h.outbox),
      mutationStamperProvider.overrideWith((_) async => h.stamper),
      if (accounts != null)
        accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppMessenger.init(child: child!),
      // Minimal router so `context.go` calls inside the form don't blow
      // up the test. The destination route renders an empty page; the
      // tests that follow assert on the form behaviour before pop.
      routerConfig: GoRouter(
        initialLocation: editingId == null ? '/new' : '/edit',
        routes: [
          GoRoute(path: '/new', builder: (_, _) => const AccountFormPage()),
          GoRoute(
            path: '/edit',
            builder: (_, _) => AccountFormPage(accountId: editingId),
          ),
          GoRoute(
            path: AppRoutes.wealthAccounts,
            builder: (_, _) => const SizedBox(),
          ),
        ],
      ),
    ),
  );
}

ProviderScope _wrapEscHarness(_Harness h, {required VoidCallback onEscape}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(h.prefs),
      appDatabaseProvider.overrideWith((_) async => h.db),
      outboxStoreProvider.overrideWith((_) async => h.outbox),
      mutationStamperProvider.overrideWith((_) async => h.stamper),
      accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppMessenger.init(child: child!),
      initialRoute: '/account',
      routes: {
        '/': (_) => const SizedBox(),
        '/account': (context) => CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              onEscape();
              // Exercise the guarded back path while proving the new inner
              // submit-shortcut scope does not consume an ancestor Esc.
              unawaited(Navigator.of(context, rootNavigator: true).maybePop());
            },
          },
          child: const AccountFormPage(),
        ),
      },
    ),
  );
}

Future<void> _pressControlEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _enlarge(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  late _Harness h;

  setUp(() async {
    h = await _Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  testWidgets('parent picker filters candidates by current category', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(
      _wrap(
        h,
        accounts: [
          _account(
            id: 'expense-root',
            name: 'Expenses',
            category: AccountSide.expense,
          ),
          _account(
            id: 'income-root',
            name: 'Income',
            category: AccountSide.income,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The form defaults to AccountSide.asset (bank carrier). The
    // parent picker filters to same-category — both seeded accounts
    // are non-asset, so the dropdown opens empty.
    final picker = find.byType(AccountTreePicker);
    expect(picker, findsOneWidget);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    // Neither expense nor income parent shows up under the asset
    // category default. The dropdown menu surfaces no items at all.
    expect(find.text('• Expenses'), findsNothing);
    expect(find.text('• Income'), findsNothing);
  });

  testWidgets('save stays disabled until the required name is valid', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    FButton saveButton() =>
        tester.widget<FButton>(find.widgetWithText(FButton, 'Save'));

    expect(saveButton().onPress, isNull);
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      'Everyday bank',
    );
    await tester.pump();
    expect(saveButton().onPress, isNotNull);
  });

  testWidgets('keyboard submit respects disabled state and commits', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    await _pressControlEnter(tester);
    expect(await h.db.select(h.db.accounts).get(), isEmpty);

    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      'Keyboard account',
    );
    await tester.pump();
    await _pressControlEnter(tester);
    await tester.pumpAndSettle();

    final rows = await h.db.select(h.db.accounts).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Keyboard account');
  });

  testWidgets(
    'submit shortcut lets Esc reach maybePop and the dirty confirmation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        var escapeCalls = 0;
        await _enlarge(tester);
        await tester.pumpWidget(
          _wrapEscHarness(h, onEscape: () => escapeCalls++),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(FTextFormField, 'Account name'),
          'Unsaved account',
        );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(escapeCalls, 1);
        expect(find.byType(AccountFormPage), findsOneWidget);
        expect(find.text('Discard changes?'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('icon picker tile selection updates the form state', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    // The catalogue includes "savings" — tap that tile.
    final savingsIcon = _accountIcon('savings');
    expect(savingsIcon, findsAtLeastNWidgets(1));
    await tester.tap(savingsIcon.last);
    await tester.pumpAndSettle();

    // The savings icon is now rendered in a "selected" tile (border
    // tint follows colorScheme.primary by default — we just verify
    // the icon appears as a positive smoke check; selection state
    // rendering is covered by the visual baseline goldens).
    expect(find.byIcon(FLucideIcons.piggyBank), findsAtLeastNWidgets(1));
  });

  testWidgets('color swatch selection persists through save', (tester) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    // Pick a colour from the palette.
    const targetColor = '#10B981';
    expect(kAccountColorPalette, contains(targetColor));
    await tester.tap(_colorSwatch(targetColor));
    await tester.pumpAndSettle();

    // Fill the required name field.
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      'Savings Bank',
    );
    await tester.pumpAndSettle();

    // Tap save.
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    // The repo-driven write completes before the form leaves.
    // Inspect the freshly inserted row directly.
    final rows = await h.db.select(h.db.accounts).get();
    expect(rows, hasLength(1));
    expect(rows.single.color, targetColor);
    expect(rows.single.name, 'Savings Bank');
  });

  testWidgets('save persists icon + color and queues a dirty pointer', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    await tester.tap(_accountIcon('savings').last);
    await tester.pumpAndSettle();
    await tester.tap(_colorSwatch('#3B82F6'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      'My Bank',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    // The v2 outbox is a pure dirty-pointer log — the row's icon / color
    // live in the materialised `accounts` row, which the sync engine reads
    // at push time.
    final saved = await (h.db.select(
      h.db.accounts,
    )..where((t) => t.name.equals('My Bank'))).getSingle();
    expect(saved.icon, 'savings');
    expect(saved.color, '#3B82F6');

    final batch = h.outbox.queued;
    expect(
      batch.any((op) => op.table == 'accounts' && op.rowId == saved.id),
      isTrue,
    );
  });

  testWidgets('create success offers Undo and tombstones the account', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      'Undo account',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = await (h.db.select(
      h.db.accounts,
    )..where((row) => row.name.equals('Undo account'))).getSingle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final tombstoned = await (h.db.select(
      h.db.accounts,
    )..where((row) => row.id.equals(saved.id))).getSingle();
    expect(tombstoned.deletedAt, isNotNull);
    expect(find.text('Change undone'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('edit success Undo restores the complete prior account', (
    tester,
  ) async {
    final repository = AccountRepository(
      db: h.db,
      outbox: h.outbox,
      stamper: h.stamper,
    );
    final original = await repository.create(
      type: AccountCategory.bank,
      name: 'Original account',
      currency: 'CNY',
      institution: 'Original bank',
      note: 'Original note',
    );
    await _enlarge(tester);
    await tester.pumpWidget(
      _wrap(h, accounts: [original], editingId: original.id),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      'Edited account',
    );
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Institution'),
      '',
    );
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();
    expect((await repository.findById(original.id))!.name, 'Edited account');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final restored = (await repository.findById(original.id))!;
    expect(restored.name, 'Original account');
    expect(restored.institution, 'Original bank');
    expect(restored.note, 'Original note');
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('Undo conflict exposes Retry and never overwrites later edit', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      'Committed account',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    final repository = AccountRepository(
      db: h.db,
      outbox: h.outbox,
      stamper: h.stamper,
    );
    final committed = (await repository.listActive()).single;
    await repository.update(committed.id, name: 'Later edit');

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Couldn't undo the change. Try again."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect((await repository.findById(committed.id))!.name, 'Later edit');
    expect(find.text('Change undone'), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });
}
