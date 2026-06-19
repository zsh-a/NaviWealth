// Page Objects for flow tests (docs/testing-strategy.md §4).
//
// A Page Object wraps "how to find and operate a screen" behind an
// intention-revealing API (`shell.openTab('Wealth')`), so flow Tasks read
// like user stories and survive UI refactors. Keep selectors here; keep
// assertions about *outcomes* in the `*_flow_test.dart` files.

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

import 'app_harness.dart';

/// The app shell: bottom navigation + the active primary destination.
class AppShell {
  AppShell(this.tester);

  final WidgetTester tester;

  Finder get bottomNav => find.byType(FloatingGlassNavBar);

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

  Future<void> openSettings() async {
    final action = find.byIcon(FLucideIcons.settings);
    expect(action, findsWidgets, reason: 'settings action missing');
    await tester.tap(action.last);
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

/// Activity destination entry points used by task-level flows.
class ActivityPageObject {
  ActivityPageObject(this.tester);

  final WidgetTester tester;

  Future<void> openIngestQueue() async {
    final action = find.byIcon(FLucideIcons.inbox);
    expect(action, findsWidgets, reason: 'ingest queue action missing');
    await tester.tap(action.first);
    await settle(tester);
  }
}

/// Layer 4 ingest review queue.
class IngestReviewPageObject {
  IngestReviewPageObject(this.tester);

  final WidgetTester tester;

  void expectLandedEmpty() {
    expect(find.text('Review entries'), findsWidgets);
    expect(find.text('Nothing to confirm'), findsOneWidget);
  }

  Future<void> pasteStatement(String text) async {
    final paste = find.text('Paste text');
    expect(paste, findsWidgets, reason: 'paste action missing');
    await tester.tap(paste.first);
    await settle(tester);

    expect(find.text('Paste statement text'), findsOneWidget);
    await tester.enterText(find.byType(FTextField), text);
    await settle(tester);

    final parse = find.text('Parse');
    expect(parse, findsWidgets, reason: 'parse action missing');
    await tester.tap(parse.last);
    await settle(tester);
  }

  void expectDraftVisible(String description) {
    expect(
      find.textContaining(description),
      findsWidgets,
      reason: 'imported draft not visible',
    );
  }

  void expectConfirmAllCount(int count) {
    expect(find.text('Confirm all · new only ($count)'), findsOneWidget);
  }
}

/// Global settings landing page.
class SettingsPageObject {
  SettingsPageObject(this.tester);

  final WidgetTester tester;

  void expectLanded() {
    expect(find.text('Settings'), findsWidgets);
  }

  Future<void> openBackupAndRestore() async {
    final action = find.text('Backup & Restore');
    expect(action, findsWidgets, reason: 'backup settings row missing');
    await tester.ensureVisible(action.first);
    await settle(tester);
    await tester.tap(action.first);
    await settle(tester);
  }
}

/// Settings → Backup & Restore.
class BackupPageObject {
  BackupPageObject(this.tester);

  final WidgetTester tester;

  void expectLanded() {
    expect(find.text('Backup & Restore'), findsWidgets);
    expect(find.text('Export Backup'), findsWidgets);
  }

  Future<void> exportWithPassphrase(String passphrase) async {
    final exportTile = find.text('Export Backup');
    expect(exportTile, findsWidgets, reason: 'export backup action missing');
    await tester.ensureVisible(exportTile.first);
    await settle(tester);
    await tester.tap(exportTile.first);
    await settle(tester);

    expect(find.text('Passphrase'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Passphrase'),
      passphrase,
    );
    await settle(tester);

    final export = find.text('Export');
    expect(export, findsWidgets, reason: 'export submit action missing');
    await tester.tap(export.last);
    await settle(tester);
  }

  void expectExportSucceeded() {
    expect(find.text('Backup exported successfully'), findsOneWidget);
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
