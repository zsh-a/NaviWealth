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
    await _pumpWorkspace(tester, size: const Size(1200, 900));

    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Buy Apple'), findsOneWidget);
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

RebalanceExecutionItem _reviewItem({RebalanceExecutionRequest? request}) {
  final plan = testPlan(reverseCollections: true);
  return RebalanceExecutionItem(
    id: 'review-item',
    sessionId: 'review-session',
    ownerUserId: 'owner-a',
    position: 0,
    suggestion: plan.trades.first,
    request: request,
    state: request == null
        ? RebalanceExecutionItemState.needsDetails
        : RebalanceExecutionItemState.ready,
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
  });

  RebalanceExecutionSession value;
  final RebalanceExecutionBatchResult applyResult;
  final List<String> skippedIds = [];
  int savedRequests = 0;
  int applyCalls = 0;
  RebalanceExecutionRequest? lastRequest;

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
  }) async => const RebalanceExecutionBatchResult(
    completedItemIds: [],
    failures: [],
    stopped: false,
  );
}

RebalanceExecutionSession _session({
  RebalanceExecutionSessionStatus status =
      RebalanceExecutionSessionStatus.active,
  RebalanceExecutionItemState itemState =
      RebalanceExecutionItemState.needsDetails,
  RebalanceExecutionIssue? issue,
}) {
  final plan = testPlan(reverseCollections: true);
  final request =
      itemState == RebalanceExecutionItemState.ready ||
          itemState == RebalanceExecutionItemState.applyFailed
      ? testRequest('item-1')
      : null;
  final item = RebalanceExecutionItem(
    id: 'item-1',
    sessionId: 'session-1',
    ownerUserId: 'owner-a',
    position: 0,
    suggestion: plan.trades.first,
    request: request,
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
