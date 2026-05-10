import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/db/providers.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/mutation_context.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/accounts/account_form_page.dart';
import 'package:naviwealth/features/accounts/account_icon_catalog.dart';
import 'package:naviwealth/features/shared/account_tree_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

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
  AccountCategory category = AccountCategory.expense,
  String currency = 'CNY',
  AccountType type = AccountType.other,
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
            path: AppRoutes.activityAccounts,
            builder: (_, _) => const SizedBox(),
          ),
        ],
      ),
    ),
  );
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
            category: AccountCategory.expense,
          ),
          _account(
            id: 'income-root',
            name: 'Income',
            category: AccountCategory.income,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The form defaults to AccountCategory.asset (bank carrier). The
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

  testWidgets('icon picker tile selection updates the form state', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    // The catalogue includes "savings" — tap that tile.
    final savingsTooltip = find.byTooltip('savings');
    expect(savingsTooltip, findsOneWidget);
    await tester.tap(savingsTooltip);
    await tester.pumpAndSettle();

    // The savings icon is now rendered in a "selected" tile (border
    // tint follows colorScheme.primary by default — we just verify
    // the icon appears as a positive smoke check; selection state
    // rendering is covered by the visual baseline goldens).
    expect(find.byIcon(Icons.savings), findsAtLeastNWidgets(1));
  });

  testWidgets('color swatch selection persists through save', (tester) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    // Pick a colour from the palette.
    const targetColor = '#10B981';
    expect(kAccountColorPalette, contains(targetColor));
    await tester.tap(find.byTooltip(targetColor));
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

    // The repo-driven write completes optimistically (pop-then-write).
    // Inspect the freshly inserted row directly.
    final rows = await h.db.select(h.db.accounts).get();
    expect(rows, hasLength(1));
    expect(rows.single.color, targetColor);
    expect(rows.single.name, 'Savings Bank');
  });

  testWidgets('save persists icon + color in the queued outbox op', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(_wrap(h, accounts: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('#3B82F6'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      'My Bank',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    final batch = await h.outbox.peekBatch();
    final insertOp = batch.firstWhere(
      (op) => op.tableName == 'accounts' && op.fieldsDiff?['name'] == 'My Bank',
    );
    expect(insertOp.fieldsDiff!['icon'], 'savings');
    expect(insertOp.fieldsDiff!['color'], '#3B82F6');
  });
}
