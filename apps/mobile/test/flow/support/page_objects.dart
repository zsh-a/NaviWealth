// Page Objects for flow tests (docs/testing-strategy.md §4).
//
// A Page Object wraps "how to find and operate a screen" behind an
// intention-revealing API (`shell.openTab('Wealth')`), so flow Tasks read
// like user stories and survive UI refactors. Keep selectors here; keep
// assertions about *outcomes* in the `*_flow_test.dart` files.

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'app_harness.dart';

/// The app shell: bottom navigation + the active primary destination.
class AppShell {
  AppShell(this.tester);

  final WidgetTester tester;

  Finder get bottomNav => find.byType(FBottomNavigationBar);

  /// Asserts the shell mounted its bottom navigation bar.
  void expectMounted() {
    expect(bottomNav, findsOneWidget, reason: 'app shell bottom nav missing');
  }

  /// Whether a primary destination with [label] is reachable from the nav.
  bool hasTab(String label) => find
      .descendant(of: bottomNav, matching: find.text(label))
      .evaluate()
      .isNotEmpty;

  /// Taps the primary destination labelled [label] and lets it settle.
  Future<void> openTab(String label) async {
    final tab = find.descendant(of: bottomNav, matching: find.text(label));
    expect(tab, findsWidgets, reason: 'no "$label" tab in bottom nav');
    await tester.tap(tab.first);
    await settle(tester);
  }
}

/// The home ("Today") destination — the FinanceOS landing surface.
class HomePage {
  HomePage(this.tester);

  final WidgetTester tester;

  /// Asserts the user has landed on Today (the default route after boot).
  void expectLanded() {
    expect(
      find.text('Today'),
      findsWidgets,
      reason: 'expected to land on the Today home surface',
    );
  }
}

/// Wealth destination entry points used by task-level flows.
class WealthPage {
  WealthPage(this.tester);

  final WidgetTester tester;

  Future<void> openAccounts() async {
    final card = find.text('Accounts');
    expect(card, findsWidgets, reason: 'accounts entry missing on Wealth');
    await tester.tap(card.first);
    await settle(tester);
  }
}

/// Accounts list surface.
class AccountsPageObject {
  AccountsPageObject(this.tester);

  final WidgetTester tester;

  void expectEmptyState() {
    expect(
      find.textContaining('No accounts yet'),
      findsOneWidget,
      reason: 'expected first-run accounts empty state',
    );
  }

  Future<void> startNewAccount() async {
    final action = find.text('New account');
    expect(action, findsWidgets, reason: 'new-account action missing');
    await tester.tap(action.last);
    await settle(tester);
  }

  void expectAccountVisible(String name) {
    expect(find.text(name), findsWidgets, reason: 'saved account not visible');
  }
}

/// New/edit account form.
class AccountFormObject {
  AccountFormObject(this.tester);

  final WidgetTester tester;

  void expectCreateMode() {
    expect(find.text('New account'), findsWidgets);
    expect(find.widgetWithText(FTextFormField, 'Account name'), findsOneWidget);
  }

  Future<void> enterName(String name) async {
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Account name'),
      name,
    );
    await settle(tester);
  }

  Future<void> save() async {
    final save = find.widgetWithText(FButton, 'Save');
    expect(save, findsOneWidget);
    await tester.tap(save);
    await settle(tester);
  }
}
