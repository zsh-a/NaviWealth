// Page Objects for flow tests (docs/development/testing-strategy.md §4).
//
// A Page Object wraps "how to find and operate a screen" behind an
// intention-revealing API (`shell.openTab('Wealth')`), so flow Tasks read
// like user stories and survive UI refactors. Keep selectors here; keep
// assertions about *outcomes* in the `*_flow_test.dart` files.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/ui/chat_composer.dart';
import 'package:naviwealth/features/finance/shared/ui/account_tree_picker.dart';

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

  Future<void> openAi() async {
    final action = find.byKey(const ValueKey<String>('floating-nav.assistant'));
    expect(action, findsWidgets, reason: 'AI center action missing');
    await tester.tap(action.first);
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

/// Shell-level AI assistant sheet.
class AiChatSheetObject {
  AiChatSheetObject(this.tester);

  final WidgetTester tester;

  void expectReady() {
    expect(find.byType(ChatComposer), findsOneWidget);
    expect(find.text('AI assistant'), findsWidgets);
    expect(find.text('Ask anything about your Life OS.'), findsOneWidget);
    expect(
      find
          .descendant(
            of: find.byType(ChatComposer),
            matching: find.byType(EditableText),
          )
          .hitTestable(),
      findsOneWidget,
    );
  }

  Future<void> ask(String question) async {
    final composer = find.byType(ChatComposer);
    expect(composer, findsOneWidget);
    await tester.enterText(
      find
          .descendant(of: composer, matching: find.byType(EditableText))
          .hitTestable(),
      question,
    );
    await settle(tester);
    expect(find.text(question), findsWidgets);

    tester.widget<ChatComposer>(composer).onSend(question);
    await settle(tester);
    await settle(tester);
  }

  void expectExchange({required String question, required String answer}) {
    expect(find.textContaining(question, findRichText: true), findsWidgets);
    expect(find.textContaining(answer, findRichText: true), findsWidgets);
  }
}

/// Activity destination entry points used by task-level flows.
class ActivityPageObject {
  ActivityPageObject(this.tester);

  final WidgetTester tester;

  Future<void> openTradeEntry() async {
    final add = find.byIcon(FLucideIcons.plus);
    expect(add, findsWidgets, reason: 'activity add action missing');
    await tester.tap(add.last);
    await settle(tester);

    expect(find.text('Record activity'), findsOneWidget);
    final trade = find.byType(AppActionSheetTile);
    expect(trade, findsWidgets, reason: 'trade action missing');
    await tester.tap(trade.at(1));
    await settle(tester);
  }

  Future<void> openExpenseEntry() async {
    final add = find.byIcon(FLucideIcons.plus);
    expect(add, findsWidgets, reason: 'activity add action missing');
    await tester.tap(add.last);
    await settle(tester);

    expect(find.text('Record activity'), findsOneWidget);
    final expense = find.byType(AppActionSheetTile);
    expect(expense, findsWidgets, reason: 'expense action missing');
    await tester.tap(expense.first);
    await settle(tester);
  }

  Future<void> openTransferEntry() async {
    final add = find.byIcon(FLucideIcons.plus);
    expect(add, findsWidgets, reason: 'activity add action missing');
    await tester.tap(add.last);
    await settle(tester);

    expect(find.text('Record activity'), findsOneWidget);
    final transfer = find.byType(AppActionSheetTile);
    expect(transfer, findsWidgets, reason: 'transfer action missing');
    await tester.tap(transfer.at(2));
    await settle(tester);
  }

  Future<void> openIngestQueue() async {
    final action = find.byIcon(FLucideIcons.inbox);
    if (action.evaluate().isNotEmpty) {
      await tester.tap(action.first);
    } else {
      final moreActions = find.byIcon(FLucideIcons.ellipsis);
      expect(
        moreActions,
        findsOneWidget,
        reason: 'activity overflow action missing',
      );
      await tester.tap(moreActions);
      await settle(tester);
      final ingestAction = find.text('Review entries');
      expect(
        ingestAction,
        findsOneWidget,
        reason: 'ingest queue action missing from overflow',
      );
      await tester.tap(ingestAction);
    }
    await settle(tester);
  }

  Future<void> openExpenseList() async {
    final moreActions = find.bySemanticsLabel('More actions');
    expect(moreActions, findsOneWidget, reason: 'activity overflow missing');
    await tester.tap(moreActions);
    await settle(tester);
    final action = find.text('Expenses');
    expect(action, findsOneWidget, reason: 'expenses overflow action missing');
    await tester.tap(action);
    await settle(tester);
  }
}

/// Activity → Record trade form.
class TradeEntryPageObject {
  TradeEntryPageObject(this.tester);

  final WidgetTester tester;

  void expectCreateMode() {
    expect(find.text('Record trade'), findsWidgets);
    expect(find.text('Asset search'), findsOneWidget);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('Valuation adjust'), findsNothing);
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('Price'), findsOneWidget);
  }
}

/// Activity -> New expense form.
class ExpenseFormObject {
  ExpenseFormObject(this.tester);

  final WidgetTester tester;

  void expectCreateMode() {
    expect(find.text('New expense'), findsWidgets);
    expect(find.widgetWithText(FTextFormField, 'Amount'), findsOneWidget);
    expect(find.text('Category'), findsWidgets);
    expect(find.text('Account'), findsWidgets);
  }

  Future<void> enterAmount(String amount) async {
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Amount'),
      amount,
    );
    await settle(tester);
  }

  Future<void> enterNote(String note) async {
    var field = find.widgetWithText(FTextFormField, 'Notes');
    if (field.evaluate().isEmpty) {
      final disclosure = find.text('Date & note');
      expect(
        disclosure,
        findsOneWidget,
        reason: 'expense advanced-fields disclosure missing',
      );
      await tester.tap(disclosure);
      await settle(tester);
      field = find.widgetWithText(FTextFormField, 'Notes');
    }
    expect(field, findsOneWidget);
    await tester.ensureVisible(field);
    await settle(tester);
    await tester.enterText(field, note);
    await settle(tester);
  }

  Future<void> save() async {
    final save = find.widgetWithText(FButton, 'Save');
    expect(save, findsOneWidget);
    await tester.tap(save);
    await settle(tester);
    await settle(tester);
  }
}

/// Activity -> Expenses list.
class ExpenseListPageObject {
  ExpenseListPageObject(this.tester);

  final WidgetTester tester;

  void expectExpenseVisible(String note) {
    expect(find.textContaining(note), findsWidgets);
  }
}

/// Activity -> Transfer form.
class TransferFormObject {
  TransferFormObject(this.tester);

  final WidgetTester tester;

  void expectCreateMode() {
    expect(find.text('Transfer'), findsWidgets);
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'Transfer'), findsOneWidget);
  }

  Future<void> selectFromAccount(String accountName) async {
    await _selectAccount(pickerIndex: 0, accountName: accountName);
  }

  Future<void> selectToAccount(String accountName) async {
    await _selectAccount(pickerIndex: 1, accountName: accountName);
  }

  Future<void> enterAmount(String amount, {String currency = 'CNY'}) async {
    final field = find.widgetWithText(FTextFormField, 'Amount ($currency)');
    expect(field, findsOneWidget);
    await tester.enterText(field, amount);
    await settle(tester);
  }

  Future<void> enterNote(String note) async {
    final field = find.widgetWithText(FTextFormField, 'Notes');
    expect(field, findsOneWidget);
    await tester.ensureVisible(field);
    await settle(tester);
    await tester.enterText(field, note);
    await settle(tester);
  }

  Future<void> save() async {
    final save = find.widgetWithText(FButton, 'Transfer');
    expect(save, findsOneWidget);
    await tester.tap(save);
    await settle(tester);
    await settle(tester);
  }

  Future<void> _selectAccount({
    required int pickerIndex,
    required String accountName,
  }) async {
    await tester.tap(find.byType(AccountTreePicker).at(pickerIndex));
    await settle(tester);
    await tester.tap(find.text(accountName).last);
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

  Future<void> pasteStatement(
    String text, {
    String completionText = 'Confirm all',
  }) async {
    var paste = find.text('Paste text');
    if (paste.evaluate().isEmpty) {
      final addSource = find.bySemanticsLabel('Add source');
      expect(addSource, findsOneWidget, reason: 'capture source menu missing');
      Finder tappableSource = addSource.hitTestable();
      for (var i = 0; i < 100 && tappableSource.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tappableSource = addSource.hitTestable();
      }
      expect(
        tappableSource,
        findsOneWidget,
        reason: 'capture source menu stayed obscured',
      );
      await tester.tap(tappableSource);
      await settle(tester);
      paste = find.text('Paste text');
    }
    expect(paste, findsWidgets, reason: 'paste action missing');
    await tester.tap(paste.first);
    await settle(tester);

    expect(find.text('Paste statement text'), findsOneWidget);
    await tester.enterText(find.byType(FTextField), text);
    await settle(tester);

    final parse = find.text('Parse');
    expect(parse, findsWidgets, reason: 'parse action missing');
    await tester.tap(parse.last);
    await settleUntil(tester, find.textContaining(completionText));
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

  Future<void> confirmAllFresh(int count) async {
    final confirm = find.text('Confirm all · new only ($count)');
    expect(confirm, findsOneWidget, reason: 'confirm-all action missing');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await settleUntil(tester, find.text('Nothing to confirm'));
    expect(
      find.text('Nothing to confirm'),
      findsOneWidget,
      reason: 'confirmed drafts did not leave the review queue',
    );
  }

  void expectDuplicateCount(int count) {
    expect(find.text('Duplicate'), findsNWidgets(count));
    expect(
      find.textContaining('Confirm all · new only'),
      findsNothing,
      reason: 'exact duplicates must not be batch-confirmable',
    );
  }

  Future<void> skipDraft(String description) async {
    final card = find.ancestor(
      of: find.textContaining(description).first,
      matching: find.byType(SoftCard),
    );
    expect(card, findsOneWidget, reason: 'draft card missing for $description');
    final skip = find.descendant(
      of: card,
      matching: find.widgetWithText(AppActionButton, 'Skip'),
    );
    expect(
      skip,
      findsOneWidget,
      reason: 'skip action missing for $description',
    );
    for (var i = 0; i < 100; i++) {
      if (tester.widget<AppActionButton>(skip).onPress != null) break;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    final onPress = tester.widget<AppActionButton>(skip).onPress;
    expect(
      onPress,
      isNotNull,
      reason: 'skip action stayed disabled for $description',
    );
    await tester.ensureVisible(skip);
    await tester.pumpAndSettle();
    await tester.tap(skip);
    await settleUntil(tester, find.text('Undo'));
    expect(find.text('Undo'), findsOneWidget, reason: 'skip did not complete');
    for (var i = 0; i < 20; i++) {
      if (find.textContaining(description).evaluate().isEmpty) return;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  }

  Future<void> undoLastAction() async {
    final undo = find.text('Undo');
    expect(undo, findsOneWidget, reason: 'undo toast action missing');
    var tappableUndo = undo.hitTestable();
    for (var i = 0; i < 20 && tappableUndo.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tappableUndo = undo.hitTestable();
    }
    expect(
      tappableUndo,
      findsOneWidget,
      reason: 'undo action stayed offscreen',
    );
    await tester.tap(tappableUndo);
    await settle(tester);
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

  Future<void> openDomains() async {
    final action = find.text('Domain management');
    expect(action, findsWidgets, reason: 'domains settings row missing');
    await tester.ensureVisible(action.first);
    await settle(tester);
    await tester.tap(action.first);
    await settle(tester);
  }
}

class DomainsPageObject {
  DomainsPageObject(this.tester);

  final WidgetTester tester;

  void expectLanded() {
    expect(find.text('Domain management'), findsWidgets);
    expect(find.text('KnowledgeOS'), findsOneWidget);
    expect(find.text('ExecutionOS'), findsOneWidget);
  }

  Future<void> enable(String label) async {
    final card = find.ancestor(
      of: find.text(label),
      matching: find.byType(AppGroupedSurface),
    );
    final toggle = find.descendant(of: card, matching: find.byType(FSwitch));
    expect(toggle, findsOneWidget, reason: '$label toggle missing');
    await tester.ensureVisible(toggle);
    await settle(tester);
    await tester.tap(toggle);
    await settle(tester);
  }
}

class KnowledgeInboxPageObject {
  KnowledgeInboxPageObject(this.tester);

  final WidgetTester tester;

  void expectLanded() => expect(find.text('Inbox'), findsWidgets);

  Future<void> captureNote(String body) async {
    final add = find.bySemanticsLabel('New capture');
    expect(add, findsOneWidget, reason: 'knowledge capture action missing');
    await tester.tap(add);
    await settle(tester);

    await tester.enterText(find.widgetWithText(FTextField, 'Content'), body);
    await tester.tap(find.text('Note').last);
    await settle(tester);
    await tester.tap(find.text('Save as Note').last);
    await settle(tester);
  }

  void expectNoteVisible(String body) {
    expect(find.textContaining(body), findsWidgets);
  }
}

class LifePageObject {
  LifePageObject(this.tester);

  final WidgetTester tester;

  void expectSignal(String title) => expect(find.text(title), findsOneWidget);

  Future<void> openSignal(String title) async {
    expectSignal(title);
    await tester.tap(find.text(title));
    await settle(tester);
  }

  void expectEvidence(String value) {
    expect(find.text('Why this appeared'), findsOneWidget);
    expect(find.text(value), findsWidgets);
  }

  Future<void> createAction(String actionTitle) async {
    expect(find.text(actionTitle), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FButton, 'Create action').hitTestable().last,
    );
    await settle(tester);
    expect(find.text('Create this action?'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FButton, 'Create action').hitTestable().last,
    );
    await settle(tester);
  }

  Future<void> openExecution() async {
    await tester.tap(find.text('Open Execution').last);
    await settle(tester);
  }
}

class ExecutionTodayPageObject {
  ExecutionTodayPageObject(this.tester);

  final WidgetTester tester;

  void expectAction(String title) => expect(find.text(title), findsOneWidget);

  Future<void> completeAction(String title) async {
    expect(find.text(title), findsOneWidget);
    final menu = find.bySemanticsLabel('More actions').hitTestable();
    expect(menu, findsOneWidget, reason: 'action overflow menu missing');
    await tester.tap(menu);
    await settle(tester);
    await tester.tap(find.text('Done').last);
    await settle(tester);
  }
}

class ExecutionReviewPageObject {
  ExecutionReviewPageObject(this.tester);

  final WidgetTester tester;

  void expectCompletedAction(String title) {
    expect(find.text('Recent closed actions'), findsWidgets);
    expect(find.text(title), findsOneWidget);
  }

  void expectOutcome(String summary) {
    expect(find.text(summary), findsOneWidget);
  }
}

/// Settings → Backup & Restore.
class BackupPageObject {
  BackupPageObject(this.tester);

  final WidgetTester tester;

  void expectLanded() {
    expect(find.text('Backup & Restore'), findsWidgets);
    expect(find.text('Export Backup'), findsWidgets);
    expect(find.text('Import Backup'), findsWidgets);
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

  Future<void> importWithPassphrase(String passphrase) async {
    final importTile = find.text('Import Backup');
    expect(importTile, findsWidgets, reason: 'import backup action missing');
    await tester.ensureVisible(importTile.first);
    await settle(tester);
    await tester.tap(importTile.first);
    await settle(tester);

    expect(find.text('Restore Backup'), findsWidgets);
    expect(
      find.text(
        'This will replace ALL local data with the contents of the backup. This cannot be undone. Continue?',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Passphrase'),
      passphrase,
    );
    await settle(tester);

    final restore = find.text('Restore');
    expect(restore, findsWidgets, reason: 'restore submit action missing');
    await tester.tap(restore.last);
    await settle(tester);
  }

  void expectImportSucceeded({required int rows}) {
    expect(
      find.text('Backup restored successfully. $rows rows imported.'),
      findsOneWidget,
    );
  }
}

/// Plan destination entry points used by task-level flows.
class PlanPageObject {
  PlanPageObject(this.tester);

  final WidgetTester tester;

  Future<void> openFireReport() async {
    final configure = find.text('Set up plan');
    final action = configure.evaluate().isNotEmpty
        ? configure
        : find.text('See plan');
    expect(action, findsOneWidget, reason: 'FIRE planning action missing');
    await tester.tap(action);
    await settle(tester);
  }

  Future<void> openRebalance() async {
    final action = find.text('Rebalance');
    expect(action, findsWidgets, reason: 'rebalance planning action missing');
    await tester.tap(action.first);
    await settle(tester);
  }

  Future<void> openBudget() async {
    final action = find.text('Budget');
    expect(action, findsWidgets, reason: 'budget planning action missing');
    await tester.tap(action.first);
    await settle(tester);
  }

  Future<void> openIncomeStrategy() async {
    var action = find.text('Income strategy');
    if (action.evaluate().isEmpty) {
      final strategies = find.text('Strategies');
      expect(
        strategies,
        findsOneWidget,
        reason: 'strategy tools disclosure missing',
      );
      await tester.tap(strategies);
      await settle(tester);
      action = find.text('Income strategy');
    }
    expect(action, findsWidgets, reason: 'income strategy action missing');
    await tester.ensureVisible(action.first);
    await settle(tester);
    await tester.tap(action.first);
    await settle(tester);
  }
}

/// Plan → FIRE report/dashboard surface.
class FireReportPageObject {
  FireReportPageObject(this.tester);

  final WidgetTester tester;

  void expectUnconfiguredReport() {
    expect(find.text('FIRE'), findsWidgets);
    expect(find.text('Set your FIRE goal'), findsOneWidget);
    expect(find.text('Set goal'), findsOneWidget);
  }
}

/// Plan → Rebalance execution surface.
class RebalancePageObject {
  RebalancePageObject(this.tester);

  final WidgetTester tester;

  void expectEmptyPlan() {
    expect(find.text('Rebalance'), findsWidgets);
    expect(find.text('No data yet'), findsOneWidget);
    expect(
      find.text(
        'Add assets to see your allocation drift and rebalance suggestions.',
      ),
      findsOneWidget,
    );
  }
}

/// Plan -> Budget surface.
class BudgetPageObject {
  BudgetPageObject(this.tester);

  final WidgetTester tester;

  void expectBudgetVisible(String categoryId) {
    expect(find.text('Budget'), findsWidgets);
    expect(find.text(categoryId), findsOneWidget);
  }

  Future<void> editBudget({
    required String categoryId,
    required String amount,
    required String note,
    String currency = 'CNY',
  }) async {
    final tile = find.text(categoryId);
    expect(tile, findsOneWidget, reason: 'budget tile missing');
    await tester.tap(tile);
    await settle(tester);

    expect(find.text('Edit budget'), findsOneWidget);
    final amountField = find.widgetWithText(FTextField, 'Amount ($currency)');
    expect(amountField, findsOneWidget);
    await tester.enterText(amountField, amount);
    await settle(tester);

    final noteField = find.widgetWithText(FTextField, 'Note');
    expect(noteField, findsOneWidget);
    await tester.enterText(noteField, note);
    await settle(tester);

    final save = find.widgetWithText(FButton, 'Save');
    expect(save, findsWidgets);
    await tester.tap(save.last);
    await settle(tester);
    await settle(tester);
  }

  void expectNoteVisible(String note) {
    expect(find.text(note), findsOneWidget);
  }
}

/// Plan → Income Planner surface.
class IncomePlannerPageObject {
  IncomePlannerPageObject(this.tester);

  final WidgetTester tester;

  void expectStartState() {
    expect(find.text('Income Planner'), findsWidgets);
    expect(find.text('Set up your stance'), findsOneWidget);
    expect(find.text('Configure preferences'), findsOneWidget);
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

  Future<void> openPortfolio() async {
    final card = find.text('Holdings');
    expect(card, findsWidgets, reason: 'portfolio entry missing on Wealth');
    await tester.tap(card.first);
    await settle(tester);
  }
}

/// Wealth → Portfolio analysis surface.
class PortfolioAnalysisPageObject {
  PortfolioAnalysisPageObject(this.tester);

  final WidgetTester tester;

  void expectEmptyAnalysis() {
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('Market value'), findsOneWidget);
    expect(find.text('Allocation'), findsOneWidget);
    expect(find.text('Positions'), findsWidgets);
    expect(find.text('No investment holdings yet.'), findsWidgets);
  }
}

/// Accounts list surface.
class AccountsPageObject {
  AccountsPageObject(this.tester);

  final WidgetTester tester;

  void expectEmptyState() {
    expect(
      find.textContaining('Add your first account'),
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

  Future<void> openAccount(String name) async {
    expectAccountVisible(name);
    await tester.tap(find.text(name).first);
    await settle(tester);
  }

  Future<void> editOpenAccount() async {
    final edit = find.bySemanticsLabel('Edit account');
    expect(edit, findsOneWidget, reason: 'account edit action missing');
    await tester.tap(edit);
    await settle(tester);
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

  void expectEditMode(String name) {
    expect(find.text(name), findsWidgets);
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
