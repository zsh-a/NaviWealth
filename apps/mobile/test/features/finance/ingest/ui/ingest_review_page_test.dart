import 'dart:async';
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_feedback.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_policy.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_source.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/finance/ingest/data/providers.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/ingest/ui/ingest_review_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';

late SharedPreferences _sharedPreferences;

class _NoopApplier implements ProposalApplier {
  const _NoopApplier();

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async =>
      throw UnsupportedError('not used');

  @override
  Future<void> undo(ProposalApplyState state) async {}
}

class _FixedCaptureSource implements IngestCaptureSource {
  _FixedCaptureSource(this.outcome);

  final IngestCaptureOutcome outcome;
  var calls = 0;

  @override
  Future<IngestCaptureOutcome> pickFile() async {
    calls++;
    return outcome;
  }
}

class _SequenceCaptureSource implements IngestCaptureSource {
  _SequenceCaptureSource(this.outcomes);

  final List<IngestCaptureOutcome> outcomes;
  var calls = 0;

  @override
  Future<IngestCaptureOutcome> pickFile() async {
    final outcome = outcomes[calls.clamp(0, outcomes.length - 1)];
    calls++;
    return outcome;
  }
}

class _DelayedCaptureSource implements IngestCaptureSource {
  final result = Completer<IngestCaptureOutcome>();
  var calls = 0;

  @override
  Future<IngestCaptureOutcome> pickFile() {
    calls++;
    return result.future;
  }
}

class _RecordingIngestController extends IngestController {
  _RecordingIngestController(super.ref, this.sources);

  final List<IngestSource> sources;

  @override
  Future<IngestResult> ingest(IngestSource source) async {
    sources.add(source);
    return const IngestResult(drafts: []);
  }
}

class _RecordingApplier implements ProposalApplier {
  final List<ProposalApplyState> undone = [];
  final Set<String> failUndoEntityIds = {};
  var applyCount = 0;
  var failUndo = false;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    applyCount++;
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: 'entry-${plan.proposalId}',
      appliedTable: 'journal_entries',
      appliedAt: DateTime.utc(2026, 5, 10),
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    undone.add(state);
    if (failUndo || failUndoEntityIds.contains(state.appliedEntityId)) {
      throw StateError('undo unavailable');
    }
  }
}

class _FailingLifecycleStore implements IngestDraftLifecycleStore {
  _FailingLifecycleStore(
    this.delegate, {
    this.confirmFailures = 0,
    this.pendingFailures = 0,
    Set<String> failConfirmDraftIds = const {},
  }) : failConfirmDraftIds = {...failConfirmDraftIds};

  final IngestDraftStore delegate;
  int confirmFailures;
  int pendingFailures;
  final Set<String> failConfirmDraftIds;

  @override
  Future<IngestLifecycleMutationResult> transition(
    IngestLifecycleTransition transition,
  ) async {
    if (transition.nextStatus == DraftStatus.confirmed &&
        (confirmFailures > 0 ||
            failConfirmDraftIds.remove(transition.draftId))) {
      if (confirmFailures > 0) confirmFailures--;
      throw StateError('confirm status unavailable');
    }
    if (transition.expectedStatus == DraftStatus.confirmed &&
        transition.nextStatus == DraftStatus.pending &&
        pendingFailures > 0) {
      pendingFailures--;
      throw StateError('pending status unavailable');
    }
    return delegate.transition(transition);
  }
}

final _account = Account(
  id: 'account-1',
  type: AccountCategory.bank,
  name: 'Daily account',
  currency: 'CNY',
  category: AccountSide.asset,
  sync: SyncMeta(
    ownerUserId: 'u1',
    updatedAt: DateTime.utc(2026, 5, 10),
    updatedByDevice: 'test',
    hlc: Hlc.zero('test'),
  ),
);

IngestDraft _draft({
  String id = 'draft-1',
  String description = 'Coffee receipt',
}) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 5, 10),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: description,
    amountMinor: -3850,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 5, 10),
  ),
  verdict: DedupVerdict.newTxn,
  status: DraftStatus.pending,
);

Widget _app({
  required IngestDraftStore store,
  required IngestConfirmService service,
  bool failLedgerRead = false,
  List<Account> accounts = const [],
  Stream<List<Account>>? accountsStream,
  bool touch = false,
  TextScaler textScaler = TextScaler.noScaling,
  IngestCaptureSource? captureSource,
  int? captureTextLimit,
  List<IngestSource>? ingestedSources,
  IngestCaptureFeedbackQueue? captureFeedbackQueue,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_sharedPreferences),
      ingestDraftStoreProvider.overrideWithValue(store),
      ingestConfirmServiceProvider.overrideWith((_) async => service),
      accountsStreamProvider.overrideWith(
        (_) => accountsStream ?? Stream.value(accounts),
      ),
      if (captureSource != null)
        ingestCaptureSourceProvider.overrideWithValue(captureSource),
      if (captureTextLimit != null)
        ingestCaptureTextLimitProvider.overrideWithValue(captureTextLimit),
      if (ingestedSources != null)
        ingestControllerProvider.overrideWith(
          (ref) => _RecordingIngestController(ref, ingestedSources),
        ),
      if (captureFeedbackQueue != null)
        ingestCaptureFeedbackQueueProvider.overrideWith(
          () => captureFeedbackQueue,
        ),
      if (failLedgerRead)
        journalEntryRepositoryProvider.overrideWith(
          (_) => throw StateError('ledger unavailable'),
        ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(compact: !touch),
      locale: const Locale('en', 'US'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: textScaler),
          child: AppMessenger.init(child: child!),
        );
      },
      home: FTheme(
        data: buildAppForuiTheme(brightness: Brightness.light, touch: touch),
        child: const IngestReviewPage(),
      ),
    ),
  );
}

Future<void> _tapCaptureOption(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  await tester.tap(find.bySemanticsLabel('Add source'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _settleUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _sharedPreferences = await SharedPreferences.getInstance();
  });

  testWidgets(
    'desktop master-detail selection dismisses only selected drafts',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      await store.putAll([
        _draft(id: 'draft-1', description: 'Coffee receipt'),
        _draft(id: 'draft-2', description: 'Metro receipt'),
      ]);
      final service = IngestConfirmService(
        applier: const _NoopApplier(),
        store: store,
      );
      await tester.pumpWidget(
        _app(store: store, service: service, accounts: [_account]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MasterDetailLayout), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Skip').last);
      await tester.pumpAndSettle();

      expect(await store.countByStatus(DraftStatus.dismissed), 1);
      expect(await store.countByStatus(DraftStatus.pending), 1);
    },
  );

  testWidgets(
    'desktop master defaults to the first actionable draft without focusing',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      await store.putAll([
        _draft(id: 'draft-readonly', description: 'Unreadable recovery'),
        _draft(id: 'draft-actionable', description: 'Actionable receipt'),
      ]);
      await db.customStatement(
        'UPDATE ingest_drafts SET recovery_kind = ?, '
        'recovery_apply_state_json = ? WHERE draft_id = ?',
        ['finalize_applied', '{not-json', 'draft-readonly'],
      );
      final service = IngestConfirmService(
        applier: const _NoopApplier(),
        store: store,
      );

      await tester.pumpWidget(
        _app(store: store, service: service, accounts: [_account]),
      );
      await tester.pumpAndSettle();

      final focused = tester.widget<Semantics>(
        find.byKey(const ValueKey('ingest-master-draft-actionable')),
      );
      expect(focused.properties.selected, isTrue);
      expect(focused.properties.enabled, isTrue);
      expect(focused.properties.onTap, isNotNull);
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .map((checkbox) => checkbox.semanticLabel),
        contains('Actionable receipt'),
      );
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        isNot('ingest review master'),
      );
      expect(find.widgetWithText(AppActionButton, 'Record'), findsOneWidget);
      expect(find.widgetWithText(AppActionButton, 'Skip'), findsOneWidget);
    },
  );

  testWidgets('desktop empty queue settles without rescheduling focus', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );

    await tester.pumpWidget(
      _app(store: store, service: service, accounts: [_account]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MasterDetailLayout), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop focus falls back when the focused draft is removed', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([
      _draft(id: 'draft-1', description: 'Coffee receipt'),
      _draft(id: 'draft-2', description: 'Metro receipt'),
    ]);
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );

    await tester.pumpWidget(
      _app(store: store, service: service, accounts: [_account]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppActionButton, 'Skip'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('ingest-master-draft-2')),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(find.text('Metro receipt'), findsNWidgets(2));
  });

  testWidgets('desktop Enter focuses detail and Space only changes selection', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft()]);
    final applier = _RecordingApplier();
    final service = IngestConfirmService(applier: applier, store: store);
    await tester.pumpWidget(
      _app(store: store, service: service, accounts: [_account]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coffee receipt').first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(find.text('Coffee receipt'), findsNWidgets(2));
    expect(find.text('1 selected'), findsOneWidget);
    expect(applier.applyCount, 0);
  });

  testWidgets('wide loading and error states keep capture actions available', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final loading = StreamController<List<Account>>();
    addTearDown(loading.close);

    await tester.pumpWidget(
      _app(store: store, service: service, accountsStream: loading.stream),
    );
    await tester.pump();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Import file'), findsOneWidget);
    expect(find.text('Paste text'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        store: store,
        service: service,
        accountsStream: Stream.error(StateError('accounts unavailable')),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Import file'), findsOneWidget);
    expect(find.text('Paste text'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch actions stay 48dp, named, and stable at 2x text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        store: store,
        service: service,
        touch: true,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppHeaderAction), findsOneWidget);
    expect(find.byType(AppActionButton), findsNothing);
    for (final action in find.byType(AppHeaderAction).evaluate()) {
      expect(
        tester.getSize(find.byElementPredicate((e) => e == action)),
        const Size(48, 48),
      );
    }
    expect(find.semantics.byLabel('Add source'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Add source'));
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('Take photo'), findsOneWidget);
    expect(find.semantics.byLabel('Import file'), findsOneWidget);
    expect(find.semantics.byLabel('Paste text'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('wide low-height account select reaches the last account at 2x', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft()]);
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final accounts = List<Account>.generate(
      20,
      (index) =>
          _account.copyWith(id: 'account-$index', name: 'Account $index'),
    );

    await tester.pumpWidget(
      _app(
        store: store,
        service: service,
        accounts: accounts,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account 0 · CNY'));
    await tester.pumpAndSettle();
    final last = find.text('Account 19 · CNY');
    await tester.ensureVisible(last);
    await tester.tap(last);
    await tester.pumpAndSettle();

    expect(find.text('Account 19 · CNY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty paste stays open and shows inline validation', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    await tester.pumpWidget(_app(store: store, service: service));
    await tester.pumpAndSettle();

    await _tapCaptureOption(tester, 'Paste text');
    await tester.tap(find.text('Parse'));
    await tester.pumpAndSettle();

    expect(find.text('Paste statement text'), findsOneWidget);
    expect(find.text('Paste statement text before parsing.'), findsOneWidget);
  });

  testWidgets('oversized paste stays open and preserves inline context', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    await tester.pumpWidget(
      _app(store: store, service: service, captureTextLimit: 16),
    );
    await tester.pumpAndSettle();

    await _tapCaptureOption(tester, 'Paste text');
    await tester.enterText(find.byType(FTextField), '12345678901234567');
    await tester.tap(find.text('Parse'));
    await tester.pumpAndSettle();

    expect(find.text('Paste statement text'), findsOneWidget);
    expect(find.textContaining('16-character import limit'), findsOneWidget);
    expect(find.byType(FTextField), findsOneWidget);
  });

  testWidgets('file-picker cancellation is silent', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final captureSource = _FixedCaptureSource(const IngestCaptureCancelled());
    await tester.pumpWidget(
      _app(store: store, service: service, captureSource: captureSource),
    );
    await tester.pumpAndSettle();

    await _tapCaptureOption(tester, 'Import file');

    expect(captureSource.calls, 1);
    expect(
      tester.widget<AppHeaderAction>(find.byType(AppHeaderAction)).focusNode,
      isNotNull,
    );
    expect(
      tester
          .widget<AppHeaderAction>(find.byType(AppHeaderAction))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    expect(find.textContaining('source'), findsNothing);
  });

  testWidgets('cold-start shared failures drain once after the page mounts', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final feedbackQueue = IngestCaptureFeedbackQueue(
      initialEvents: const [
        IngestCaptureFeedbackEvent(
          id: 1,
          feedback: IngestCaptureFailureFeedback(
            IngestCaptureFailure(
              IngestCaptureFailureCode.tooLarge,
              maxBytes: IngestCaptureLimits.receiptImageBytes,
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      _app(store: store, service: service, captureFeedbackQueue: feedbackQueue),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This file exceeds the 8 MiB import limit.'),
      findsOneWidget,
    );
    await tester.pump();
    expect(
      find.text('This file exceeds the 8 MiB import limit.'),
      findsOneWidget,
    );
  });

  testWidgets('active review page consumes every new shared failure', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final feedbackQueue = IngestCaptureFeedbackQueue();
    await tester.pumpWidget(
      _app(store: store, service: service, captureFeedbackQueue: feedbackQueue),
    );
    await tester.pumpAndSettle();

    feedbackQueue
      ..enqueueCaptureFailure(
        const IngestCaptureFailure(IngestCaptureFailureCode.empty),
      )
      ..enqueueProcessingFailure(IngestProcessingFailureCode.failed);
    await tester.pumpAndSettle();

    expect(find.text('This source is empty.'), findsOneWidget);
    expect(
      find.text('Something interrupted this shared import.'),
      findsOneWidget,
    );
  });

  testWidgets('only one capture may hold its memory budget at a time', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final captureSource = _DelayedCaptureSource();
    await tester.pumpWidget(
      _app(store: store, service: service, captureSource: captureSource),
    );
    await tester.pumpAndSettle();

    await _tapCaptureOption(tester, 'Import file');
    await tester.pump();
    expect(captureSource.calls, 1);
    expect(
      tester.widget<AppHeaderAction>(find.byType(AppHeaderAction)).onPress,
      isNull,
    );

    await tester.tap(find.bySemanticsLabel('Add source'), warnIfMissed: false);
    await tester.pump();
    expect(captureSource.calls, 1);

    captureSource.result.complete(const IngestCaptureCancelled());
    await tester.pumpAndSettle();
  });

  testWidgets('a rejected drop does not block the next valid file', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final ingestedSources = <IngestSource>[];
    await tester.pumpWidget(
      _app(store: store, service: service, ingestedSources: ingestedSources),
    );
    await tester.pumpAndSettle();

    final validFile = DropItemFile.fromData(
      Uint8List.fromList(
        utf8.encode(
          'date,description,amount,currency\n'
          '2026-05-10,Coffee,-38.50,CNY',
        ),
      ),
      name: 'statement.csv',
      path: 'statement.csv',
    );

    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(
            Uint8List.fromList(const [1]),
            name: 'unsupported.docx',
            path: 'unsupported.docx',
          ),
          validFile,
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    for (var i = 0; i < 20 && ingestedSources.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();

    expect(ingestedSources, hasLength(1));
    expect(ingestedSources.single.payload, contains('Coffee'));
    expect(find.text('This file type isn’t supported.'), findsOneWidget);
  });

  testWidgets('oversized picked file shows its limit and a specific action', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final captureSource = _FixedCaptureSource(
      const IngestCaptureFailure(
        IngestCaptureFailureCode.tooLarge,
        maxBytes: IngestCaptureLimits.statementPdfBytes,
      ),
    );
    await tester.pumpWidget(
      _app(store: store, service: service, captureSource: captureSource),
    );
    await tester.pumpAndSettle();

    await _tapCaptureOption(tester, 'Import file');

    expect(
      find.text('This file exceeds the 12 MiB import limit.'),
      findsOneWidget,
    );
    expect(find.text('Choose file'), findsOneWidget);
    expect(await store.watchByStatus(DraftStatus.pending).first, isEmpty);
  });

  testWidgets('parse exception keeps an actionable retry', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    await tester.pumpWidget(
      _app(store: store, service: service, failLedgerRead: true),
    );
    await tester.pumpAndSettle();

    await _tapCaptureOption(tester, 'Paste text');
    await tester.enterText(
      find.byType(FTextField),
      'date,description,amount\n2026-05-10,Coffee,-38.50',
    );
    await tester.tap(find.text('Parse'));
    await _settleUntil(
      tester,
      find.text('Couldn’t parse this import. Try again.'),
    );
    expect(find.text('Couldn’t parse this import. Try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('skip exposes undo and restores the original draft', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft()]);
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    await tester.pumpWidget(_app(store: store, service: service));
    await tester.pumpAndSettle();

    expect(find.text('Coffee receipt'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppActionButton, 'Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee receipt'), findsNothing);
    expect(find.text('Entry skipped'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee receipt'), findsOneWidget);
    expect(find.text('Entry restored'), findsOneWidget);
  });

  testWidgets('confirm retains full state for a working undo action', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft()]);
    final applier = _RecordingApplier();
    final service = IngestConfirmService(applier: applier, store: store);
    await tester.pumpWidget(
      _app(store: store, service: service, accounts: [_account]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppActionButton, 'Record'));
    await tester.pumpAndSettle();
    expect(find.text('Coffee receipt'), findsNothing);
    expect(find.text('Recorded'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Coffee receipt'), findsOneWidget);
    expect(applier.undone.single.appliedEntityId, 'entry-draft-1');
  });

  testWidgets(
    'failed compensation blocks duplicate record and resolves state',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      await store.putAll([_draft()]);
      final applier = _RecordingApplier()..failUndo = true;
      final lifecycle = _FailingLifecycleStore(store, confirmFailures: 1);
      final service = IngestConfirmService(applier: applier, store: lifecycle);
      await tester.pumpWidget(
        _app(store: store, service: service, accounts: [_account]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppActionButton, 'Record'));
      await tester.pumpAndSettle();

      expect(find.text('Coffee receipt'), findsOneWidget);
      expect(find.widgetWithText(AppActionButton, 'Record'), findsNothing);
      expect(find.text('Resolve review state'), findsOneWidget);
      expect(applier.applyCount, 1);

      // Recovery is persisted in the draft row, so a fresh page state still
      // reconstructs the finalize-only action instead of exposing Record.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _app(store: store, service: service, accounts: [_account]),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppActionButton, 'Record'), findsNothing);
      expect(find.text('Resolve review state'), findsOneWidget);

      await tester.tap(find.text('Resolve review state'));
      await tester.pumpAndSettle();

      expect(find.text('Coffee receipt'), findsNothing);
      expect(find.text('Review state resolved'), findsOneWidget);
      expect(applier.applyCount, 1);
    },
  );

  testWidgets('corrupt recovery blocks both record and confirm all', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft()]);
    await db.customStatement(
      'UPDATE ingest_drafts SET recovery_kind = ?, '
      'recovery_apply_state_json = ? WHERE draft_id = ?',
      ['finalize_applied', '{not-json', 'draft-1'],
    );
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );

    await tester.pumpWidget(
      _app(store: store, service: service, accounts: [_account]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee receipt'), findsOneWidget);
    expect(find.widgetWithText(AppActionButton, 'Record'), findsNothing);
    expect(
      find.textContaining('recovery details are unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Confirm all'), findsNothing);
  });

  testWidgets('mixed batch keeps undo for normal successes', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([
      _draft(id: 'draft-1', description: 'Coffee receipt'),
      _draft(id: 'draft-2', description: 'Metro receipt'),
    ]);
    final applier = _RecordingApplier()..failUndoEntityIds.add('entry-draft-2');
    final lifecycle = _FailingLifecycleStore(
      store,
      failConfirmDraftIds: {'draft-2'},
    );
    final service = IngestConfirmService(applier: applier, store: lifecycle);

    await tester.pumpWidget(
      _app(store: store, service: service, accounts: [_account]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm all · new only (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Metro receipt'), findsOneWidget);
    expect(find.text('Resolve review state'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee receipt'), findsOneWidget);
    expect(find.widgetWithText(AppActionButton, 'Record'), findsOneWidget);
    expect(find.text('Resolve review state'), findsOneWidget);
    expect(
      applier.undone.map((state) => state.appliedEntityId),
      contains('entry-draft-1'),
    );
    expect(
      applier.undone.map((state) => state.appliedEntityId),
      isNot(contains('entry-draft-2')),
    );
  });

  testWidgets('parse retry reopens capture without retaining its payload', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final service = IngestConfirmService(
      applier: const _NoopApplier(),
      store: store,
    );
    final captureSource = _SequenceCaptureSource([
      const IngestCaptureSuccess(
        IngestSource(
          kind: IngestSourceKind.csv,
          payload: 'date,description,amount\n2026-05-10,Coffee,-38.50',
          originLabel: 'statement.csv',
        ),
      ),
      const IngestCaptureCancelled(),
    ]);
    await tester.pumpWidget(
      _app(
        store: store,
        service: service,
        captureSource: captureSource,
        failLedgerRead: true,
      ),
    );
    await tester.pumpAndSettle();

    await _tapCaptureOption(tester, 'Import file');
    await _settleUntil(
      tester,
      find.text('Couldn’t parse this import. Try again.'),
    );
    expect(find.text('Couldn’t parse this import. Try again.'), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);

    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(captureSource.calls, 2);
  });

  testWidgets('undo restore retry does not invoke ledger undo twice', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft()]);
    final applier = _RecordingApplier();
    final lifecycle = _FailingLifecycleStore(store, pendingFailures: 1);
    final service = IngestConfirmService(applier: applier, store: lifecycle);
    await tester.pumpWidget(
      _app(store: store, service: service, accounts: [_account]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppActionButton, 'Record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(applier.undone, hasLength(1));

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee receipt'), findsOneWidget);
    expect(applier.undone, hasLength(1));
  });
}
