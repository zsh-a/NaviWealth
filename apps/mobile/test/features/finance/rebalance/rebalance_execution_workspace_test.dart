import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_execution_coordinator.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_execution_workspace_gateway.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_execution_codecs.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/finance/rebalance/ui/rebalance_execution_review_sheet.dart';
import 'package:naviwealth/features/finance/rebalance/ui/rebalance_execution_workspace_page.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';
import 'package:naviwealth/l10n/gen/app_localizations_zh.dart';

import 'data/rebalance_execution_test_fixtures.dart';

void main() {
  test('replace and archive warnings preserve ledger and disable old Undo', () {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();

    for (final copy in [
      en.rebalanceExecutionReplaceBody,
      en.rebalanceExecutionArchiveBody,
    ]) {
      expect(copy, contains('already recorded'));
      expect(copy, contains('permanently disabled'));
    }
    for (final copy in [
      zh.rebalanceExecutionReplaceBody,
      zh.rebalanceExecutionArchiveBody,
    ]) {
      expect(copy, contains('已经记账'));
      expect(copy, contains('永久关闭'));
    }
  });

  testWidgets('renders the execution queue on a narrow viewport', (
    tester,
  ) async {
    await _pumpWorkspace(tester, size: const Size(390, 844));

    expect(find.text('Execution'), findsOneWidget);
    expect(find.text('0 of 1 resolved'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.bySemanticsLabel('Archive execution'), findsOneWidget);
    expect(tester.getSize(find.byType(AppHeaderAction)), const Size(48, 48));
    for (var i = 0; i < find.byType(AppActionButton).evaluate().length; i++) {
      expect(tester.getSize(find.byType(AppActionButton).at(i)).height, 48);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps primary actions visible on a wide viewport', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1200, 900),
      session: _session(itemState: RebalanceExecutionItemState.ready),
    );

    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Buy Apple'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('rebalance-execution-progress')))
          .height,
      lessThan(160),
    );
    expect(tester.getSize(find.byType(AppHeaderAction)), const Size(40, 40));
    for (var i = 0; i < find.byType(AppActionButton).evaluate().length; i++) {
      expect(tester.getSize(find.byType(AppActionButton).at(i)).height, 40);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports enlarged text without horizontal overflow', (
    tester,
  ) async {
    await _pumpWorkspace(tester, size: const Size(390, 844), textScale: 2);

    expect(find.text('Needs details'), findsOneWidget);
    expect(find.byKey(const ValueKey('app.back')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived execution is read-only', (tester) async {
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      session: _session(status: RebalanceExecutionSessionStatus.archived),
    );

    expect(find.text('Review'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Apply'), findsNothing);
    expect(find.byIcon(FLucideIcons.archive), findsNothing);
  });

  testWidgets('recovery-blocked item exposes no unsafe mutation action', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      session: _session(itemState: RebalanceExecutionItemState.recoveryBlocked),
    );

    expect(find.text('Needs recovery'), findsOneWidget);
    expect(find.text('Review'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets(
    'mixed blocked, ready, and applied items keep safe batch actions',
    (tester) async {
      await _pumpWorkspace(
        tester,
        size: const Size(390, 844),
        textScale: 2,
        session: _mixedSession(),
      );

      expect(find.text('Needs recovery'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stop replaces every aggregate action while a batch is running', (
    tester,
  ) async {
    final session = _session(itemState: RebalanceExecutionItemState.ready);
    final completer = Completer<RebalanceExecutionBatchResult>();
    final gateway = _FakeGateway(session, applyCompleter: completer);
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      session: session,
      gateway: gateway,
    );

    await tester.tap(find.text('Apply'));
    for (var i = 0; i < 10 && gateway.applyCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(gateway.applyCalls, 1);
    await tester.pump();
    expect(find.text('Stop after current'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
    expect(find.text('Undo'), findsNothing);

    await tester.tap(find.text('Stop after current'));
    expect(gateway.lastStop?.isStopped, isTrue);
    completer.complete(
      const RebalanceExecutionBatchResult(
        completedItemIds: [],
        failures: [
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.stopped,
          ),
        ],
        stopped: true,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('undo failure retries only from the session control', (
    tester,
  ) async {
    final session = _session(
      itemState: RebalanceExecutionItemState.undoFailed,
      issue: RebalanceExecutionIssue(
        RebalanceExecutionIssueCode.undoUnavailable,
        'undo details stay private',
      ),
    );
    await _pumpWorkspace(tester, size: const Size(390, 844), session: session);

    expect(find.text('Retry undo'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Review'), findsNothing);
    expect(find.text('Add price'), findsNothing);
  });

  testWidgets('classified issue debug text is never rendered raw', (
    tester,
  ) async {
    const sentinel = 'RAW_INTERNAL_SENTINEL';
    final session = _session(
      itemState: RebalanceExecutionItemState.applyFailed,
      issue: RebalanceExecutionIssue(
        RebalanceExecutionIssueCode.internal,
        sentinel,
      ),
    );
    final gateway = _FakeGateway(session);
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      session: session,
      gateway: gateway,
    );

    expect(find.textContaining(sentinel), findsNothing);
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(gateway.skippedIds, [session.items.single.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'offline pricing exposes honest batch retry and manual price actions',
    (tester) async {
      final session = _session(
        itemState: RebalanceExecutionItemState.applyFailed,
        issue: RebalanceExecutionIssue(
          RebalanceExecutionIssueCode.applyUnavailable,
          'RAW_OFFLINE_DETAILS',
        ),
        includePrice: false,
      );
      final gateway = _FakeGateway(session);
      await _pumpWorkspace(
        tester,
        size: const Size(390, 844),
        textScale: 2,
        session: session,
        gateway: gateway,
      );

      expect(find.text('Retry execution'), findsOneWidget);
      expect(find.text('Add price'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.textContaining('RAW_OFFLINE_DETAILS'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Retry execution'));
      await tester.tap(find.text('Retry execution'));
      await tester.pumpAndSettle();
      expect(gateway.applyCalls, 1);
    },
  );

  testWidgets('existing manual price keeps temporary failure retry-only', (
    tester,
  ) async {
    final session = _session(
      itemState: RebalanceExecutionItemState.applyFailed,
      issue: RebalanceExecutionIssue(
        RebalanceExecutionIssueCode.applyUnavailable,
        'temporary failure',
      ),
    );
    await _pumpWorkspace(tester, size: const Size(390, 844), session: session);

    expect(find.text('Retry execution'), findsOneWidget);
    expect(find.text('Add price'), findsNothing);
    expect(find.text('Review'), findsNothing);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('batch exceptions render only the common safe message', (
    tester,
  ) async {
    const sentinel = 'RAW_BATCH_EXCEPTION';
    final session = _session(itemState: RebalanceExecutionItemState.ready);
    final gateway = _FakeGateway(session, applyError: StateError(sentinel));
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      session: session,
      gateway: gateway,
    );

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.textContaining(sentinel), findsNothing);
    expect(
      find.text(AppLocalizationsEn().commonSafeErrorMessage),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('skip action delegates exactly once', (tester) async {
    final session = _session();
    final gateway = _FakeGateway(session);
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      session: session,
      gateway: gateway,
    );

    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(gateway.skippedIds, [session.items.first.id]);
  });

  testWidgets('batch action surfaces typed partial result', (tester) async {
    final session = _session(itemState: RebalanceExecutionItemState.ready);
    final gateway = _FakeGateway(
      session,
      applyResult: const RebalanceExecutionBatchResult(
        completedItemIds: ['item-1'],
        failures: [
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.businessFailed,
            itemId: 'item-2',
          ),
        ],
        stopped: false,
      ),
    );
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      session: session,
      gateway: gateway,
    );

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(gateway.applyCalls, 1);
    expect(find.text('1 completed; 1 need attention.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('mixed batch failures use the highest safe severity', (
    tester,
  ) async {
    final session = _session(itemState: RebalanceExecutionItemState.ready);
    final gateway = _FakeGateway(
      session,
      applyResult: RebalanceExecutionBatchResult(
        completedItemIds: const [],
        failures: [
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.businessFailed,
            issue: RebalanceExecutionIssue(
              RebalanceExecutionIssueCode.applyUnavailable,
              'temporary',
            ),
          ),
          RebalanceExecutionFailure(
            code: RebalanceExecutionFailureCode.businessFailed,
            issue: RebalanceExecutionIssue(
              RebalanceExecutionIssueCode.internal,
              'fatal',
            ),
          ),
        ],
        stopped: true,
      ),
    );
    await _pumpWorkspace(
      tester,
      size: const Size(390, 844),
      session: session,
      gateway: gateway,
    );

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.byIcon(FLucideIcons.circleX), findsOneWidget);
    expect(find.text('The batch stopped; 2 need attention.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('new review never infers quantity or price', (tester) async {
    final item = _reviewItem();
    final gateway = _FakeGateway(_session());
    await _pumpReviewEditor(tester, item: item, gateway: gateway);

    expect(
      tester.widget<EditableText>(_amountField('Quantity')).controller.text,
      isEmpty,
    );
    expect(
      tester.widget<EditableText>(_amountField('Price')).controller.text,
      isEmpty,
    );
  });

  testWidgets('missing offline price is required, focused, and saved locally', (
    tester,
  ) async {
    final request = _withPrice(testRequest('review-item'), null);
    final item = _reviewItem(
      request: request,
      issue: RebalanceExecutionIssue(
        RebalanceExecutionIssueCode.applyUnavailable,
        'offline',
      ),
    );
    final gateway = _FakeGateway(_session());
    await _pumpReviewEditor(tester, item: item, gateway: gateway);

    final priceEditor = tester.widget<EditableText>(_amountField('Price'));
    expect(priceEditor.focusNode.hasFocus, isTrue);
    expect(
      find.text(
        'Automatic pricing is unavailable. Enter a price to continue without a quote.',
      ),
      findsOneWidget,
    );

    await tester.enterText(_amountField('Price'), '0');
    await tester.ensureVisible(find.text('Save review'));
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();
    expect(gateway.savedRequests, 0);
    expect(find.text('Amount must be greater than zero'), findsOneWidget);

    await tester.enterText(_amountField('Price'), '123.45');
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();

    expect(gateway.savedRequests, 1);
    expect(gateway.lastRequest?.price, Decimal.parse('123.45'));
    expect(gateway.applyCalls, 0);
    expect(gateway.undoCalls, 0);
  });

  testWidgets('review save failure preserves input and hides technical copy', (
    tester,
  ) async {
    const sentinel = 'RAW_SAVE_EXCEPTION';
    final request = _withPrice(testRequest('review-item'), null);
    final item = _reviewItem(
      request: request,
      issue: RebalanceExecutionIssue(
        RebalanceExecutionIssueCode.priceRequired,
        'missing',
      ),
    );
    final gateway = _FakeGateway(_session(), saveError: StateError(sentinel));
    await _pumpReviewEditor(tester, item: item, gateway: gateway);

    await tester.enterText(_amountField('Price'), '88.50');
    await tester.ensureVisible(find.text('Save review'));
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();

    expect(find.textContaining(sentinel), findsNothing);
    expect(
      find.text(AppLocalizationsEn().commonSafeErrorMessage),
      findsOneWidget,
    );
    expect(
      tester.widget<EditableText>(_amountField('Price')).controller.text,
      '88.50',
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('cash picker excludes cash accounts in another currency', (
    tester,
  ) async {
    final item = _reviewItem();
    final snapshots = testRequest(item.id);
    final eurCash = snapshots.cashAccount!.copyWith(
      id: 'cash-eur',
      name: 'EUR Cash',
      currency: 'EUR',
    );
    await _pumpReviewEditor(
      tester,
      item: item,
      gateway: _FakeGateway(_session()),
      accounts: [snapshots.account, snapshots.cashAccount!, eurCash],
    );

    expect(find.text('EUR Cash · EUR'), findsNothing);
  });

  testWidgets('changing currency clears an incompatible cash account', (
    tester,
  ) async {
    final request = testRequest('review-item');
    final gateway = _FakeGateway(_session());
    await _pumpReviewEditor(
      tester,
      item: _reviewItem(request: request),
      gateway: gateway,
    );

    final currencySelect = find.byType(CurrencyPicker);
    await tester.ensureVisible(currencySelect);
    await tester.tap(currencySelect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR · Euro'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save review'));
    await tester.tap(find.text('Save review'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(gateway.lastRequest?.currency, 'EUR');
    expect(gateway.lastRequest?.cashAccount, isNull);
  });

  testWidgets('review rejects a non-positive quantity before gateway save', (
    tester,
  ) async {
    final request = testRequest('review-item');
    final item = _reviewItem(request: request);
    final gateway = _FakeGateway(_session());
    await _pumpReviewEditor(tester, item: item, gateway: gateway);

    await tester.enterText(_amountField('Quantity'), '0');
    await tester.ensureVisible(find.text('Save review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save review'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(gateway.savedRequests, 0);
  });
}

Finder _amountField(String label) => find.descendant(
  of: find.widgetWithText(AmountField, label),
  matching: find.byType(EditableText),
);

Future<void> _pumpReviewEditor(
  WidgetTester tester, {
  required RebalanceExecutionItem item,
  required _FakeGateway gateway,
  List<Account>? accounts,
}) async {
  tester.view
    ..physicalSize = const Size(800, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final snapshots = testRequest(item.id);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rebalanceOwnedAccountsProvider.overrideWith(
          (_) => Stream.value(
            accounts ?? [snapshots.account, snapshots.cashAccount!],
          ),
        ),
        rebalanceOwnedSecuritiesProvider.overrideWith(
          (_) => Stream.value([snapshots.asset]),
        ),
        rebalanceExecutionWorkspaceGatewayProvider.overrideWith(
          (_) async => gateway,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(compact: true),
        builder: (context, child) => AppMessenger.init(child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: buildAppForuiTheme(brightness: Brightness.dark, touch: false),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRebalanceExecutionReviewSheet(
                context: context,
                item: item,
              ),
              child: const Text('Open review'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open review'));
  await tester.pumpAndSettle();
}

RebalanceExecutionItem _reviewItem({
  RebalanceExecutionRequest? request,
  RebalanceExecutionIssue? issue,
}) {
  final plan = testPlan(reverseCollections: true);
  return RebalanceExecutionItem(
    id: 'review-item',
    sessionId: 'review-session',
    ownerUserId: 'owner-a',
    position: 0,
    suggestion: plan.trades.first,
    request: request,
    state: issue != null
        ? RebalanceExecutionItemState.applyFailed
        : request == null
        ? RebalanceExecutionItemState.needsDetails
        : RebalanceExecutionItemState.ready,
    issue: issue,
    rawRequestJson: request == null
        ? null
        : RebalanceExecutionRequestCodec.encode(request),
    createdAt: testNow,
    updatedAt: testNow,
  );
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  RebalanceExecutionSession? session,
  RebalanceExecutionWorkspaceGateway? gateway,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  final resolvedSession = session ?? _session();
  final touch = Breakpoints.isMobile(size.width);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rebalanceExecutionSessionProvider(
          resolvedSession.id,
        ).overrideWith((_) async => resolvedSession),
        if (gateway != null)
          rebalanceExecutionWorkspaceGatewayProvider.overrideWith(
            (_) async => gateway,
          ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(compact: !touch),
        builder: (context, child) => AppMessenger.init(child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: buildAppForuiTheme(brightness: Brightness.dark, touch: touch),
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: RebalanceExecutionWorkspacePage(
              sessionId: resolvedSession.id,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeGateway implements RebalanceExecutionWorkspaceGateway {
  _FakeGateway(
    this.value, {
    this.applyResult = const RebalanceExecutionBatchResult(
      completedItemIds: [],
      failures: [],
      stopped: false,
    ),
    this.applyError,
    this.saveError,
    this.applyCompleter,
  });

  RebalanceExecutionSession value;
  final RebalanceExecutionBatchResult applyResult;
  final Object? applyError;
  final Object? saveError;
  final Completer<RebalanceExecutionBatchResult>? applyCompleter;
  final List<String> skippedIds = [];
  int savedRequests = 0;
  int applyCalls = 0;
  int undoCalls = 0;
  RebalanceExecutionRequest? lastRequest;
  RebalanceStopSignal? lastStop;

  @override
  Future<RebalanceExecutionSession?> active() async => value;

  @override
  Future<void> archive(String sessionId) async {}

  @override
  Future<RebalanceExecutionBatchResult> apply(
    String sessionId, {
    RebalanceStopSignal stop = const NeverRebalanceStopSignal(),
  }) async {
    applyCalls += 1;
    lastStop = stop;
    if (applyError case final error?) throw error;
    if (applyCompleter case final completer?) return completer.future;
    return applyResult;
  }

  @override
  Future<RebalanceExecutionSession> createOrResume(RebalancePlan plan) async =>
      value;

  @override
  Future<RebalanceExecutionItem> reopen(String itemId) async =>
      value.items.firstWhere((item) => item.id == itemId);

  @override
  Future<RebalanceExecutionSession> replaceActive({
    required String expectedSessionId,
    required String expectedFingerprint,
    required RebalancePlan plan,
  }) async => value;

  @override
  Future<RebalanceExecutionItem> saveReviewedRequest({
    required RebalanceExecutionItem expected,
    required RebalanceExecutionRequest request,
  }) async {
    if (saveError case final error?) throw error;
    savedRequests += 1;
    lastRequest = request;
    return expected;
  }

  @override
  Future<RebalanceExecutionSession?> session(String sessionId) async => value;

  @override
  Future<RebalanceExecutionItem> skip(String itemId) async {
    skippedIds.add(itemId);
    return value.items.firstWhere((item) => item.id == itemId);
  }

  @override
  Future<RebalanceExecutionBatchResult> undo(
    String sessionId, {
    RebalanceStopSignal stop = const NeverRebalanceStopSignal(),
  }) async {
    undoCalls += 1;
    return const RebalanceExecutionBatchResult(
      completedItemIds: [],
      failures: [],
      stopped: false,
    );
  }
}

RebalanceExecutionSession _session({
  RebalanceExecutionSessionStatus status =
      RebalanceExecutionSessionStatus.active,
  RebalanceExecutionItemState itemState =
      RebalanceExecutionItemState.needsDetails,
  RebalanceExecutionIssue? issue,
  bool includePrice = true,
}) {
  final plan = testPlan(reverseCollections: true);
  final request =
      itemState == RebalanceExecutionItemState.ready ||
          itemState == RebalanceExecutionItemState.applyFailed ||
          itemState == RebalanceExecutionItemState.undoFailed
      ? _withPrice(
          testRequest('item-1'),
          includePrice ? Decimal.parse('123.45') : null,
        )
      : null;
  final item = RebalanceExecutionItem(
    id: 'item-1',
    sessionId: 'session-1',
    ownerUserId: 'owner-a',
    position: 0,
    suggestion: plan.trades.first,
    request: request,
    receipt: itemState == RebalanceExecutionItemState.undoFailed
        ? testReceipt('item-1')
        : null,
    state: itemState,
    issue:
        issue ??
        (itemState == RebalanceExecutionItemState.recoveryBlocked
            ? RebalanceExecutionIssue(
                RebalanceExecutionIssueCode.recoveryCorrupt,
                'corrupt persisted payload',
              )
            : null),
    rawRequestJson: request == null
        ? null
        : RebalanceExecutionRequestCodec.encode(request),
    rawReceiptJson: itemState == RebalanceExecutionItemState.undoFailed
        ? TradeMutationReceiptCodec.encode(testReceipt('item-1'))
        : null,
    appliedSequence: itemState == RebalanceExecutionItemState.undoFailed
        ? 1
        : null,
    createdAt: testNow,
    updatedAt: testNow,
  );
  return RebalanceExecutionSession(
    id: 'session-1',
    ownerUserId: 'owner-a',
    status: status,
    plan: plan,
    rawPlanJson: RebalancePlanCodec.encode(plan),
    planFingerprint: RebalancePlanFingerprint.compute(plan),
    items: [item],
    createdAt: testNow,
    updatedAt: testNow,
    archivedAt: status == RebalanceExecutionSessionStatus.archived
        ? testNow
        : null,
  );
}

RebalanceExecutionSession _mixedSession() {
  final readySession = _session(itemState: RebalanceExecutionItemState.ready);
  final plan = readySession.plan;
  final appliedRequest = _withPrice(
    testRequest('item-3'),
    Decimal.parse('123.45'),
  );
  final appliedReceipt = testReceipt('item-3');
  return RebalanceExecutionSession(
    id: readySession.id,
    ownerUserId: readySession.ownerUserId,
    status: RebalanceExecutionSessionStatus.active,
    plan: plan,
    rawPlanJson: readySession.rawPlanJson,
    planFingerprint: readySession.planFingerprint,
    items: [
      readySession.items.single,
      RebalanceExecutionItem(
        id: 'item-2',
        sessionId: readySession.id,
        ownerUserId: readySession.ownerUserId,
        position: 1,
        suggestion: plan.trades.first,
        state: RebalanceExecutionItemState.recoveryBlocked,
        issue: RebalanceExecutionIssue(
          RebalanceExecutionIssueCode.recoveryCorrupt,
          'corrupt persisted payload',
        ),
        createdAt: testNow,
        updatedAt: testNow,
      ),
      RebalanceExecutionItem(
        id: 'item-3',
        sessionId: readySession.id,
        ownerUserId: readySession.ownerUserId,
        position: 2,
        suggestion: plan.trades.first,
        request: appliedRequest,
        receipt: appliedReceipt,
        state: RebalanceExecutionItemState.applied,
        rawRequestJson: RebalanceExecutionRequestCodec.encode(appliedRequest),
        rawReceiptJson: TradeMutationReceiptCodec.encode(appliedReceipt),
        appliedSequence: 1,
        createdAt: testNow,
        updatedAt: testNow,
      ),
    ],
    createdAt: testNow,
    updatedAt: testNow,
  );
}

RebalanceExecutionRequest _withPrice(
  RebalanceExecutionRequest request,
  Decimal? price,
) => RebalanceExecutionRequest(
  transactionId: request.transactionId,
  account: request.account,
  cashAccount: request.cashAccount,
  asset: request.asset,
  type: request.type,
  quantity: request.quantity,
  price: price,
  currency: request.currency,
  tradeDate: request.tradeDate,
  fee: request.fee,
  tax: request.tax,
  note: request.note,
);
