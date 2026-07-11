import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
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

import '../../../../core/persistence/test_database.dart';

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
  Future<void> markNeedsFinalize(ConfirmedIngestItem item) =>
      delegate.markNeedsFinalize(item);

  @override
  Future<void> updateStatus(String draftId, DraftStatus status) async {
    if (status == DraftStatus.confirmed &&
        (confirmFailures > 0 || failConfirmDraftIds.remove(draftId))) {
      if (confirmFailures > 0) confirmFailures--;
      throw StateError('confirm status unavailable');
    }
    if (status == DraftStatus.pending && pendingFailures > 0) {
      pendingFailures--;
      throw StateError('pending status unavailable');
    }
    await delegate.updateStatus(draftId, status);
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
  bool touch = false,
  TextScaler textScaler = TextScaler.noScaling,
  IngestCaptureSource? captureSource,
  int? captureTextLimit,
  List<IngestSource>? ingestedSources,
  IngestCaptureFeedbackQueue? captureFeedbackQueue,
}) {
  return ProviderScope(
    overrides: [
      ingestDraftStoreProvider.overrideWithValue(store),
      ingestConfirmServiceProvider.overrideWith((_) async => service),
      accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
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

void main() {
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

    expect(find.byType(AppHeaderAction), findsNWidgets(3));
    expect(find.byType(AppActionButton), findsNWidgets(3));
    for (final action in find.byType(AppHeaderAction).evaluate()) {
      expect(
        tester.getSize(find.byElementPredicate((e) => e == action)),
        const Size(48, 48),
      );
    }
    for (final action in find.byType(AppActionButton).evaluate()) {
      expect(
        tester.getSize(find.byElementPredicate((e) => e == action)).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(find.semantics.byLabel('Take photo'), findsWidgets);
    expect(find.semantics.byLabel('Import file'), findsWidgets);
    expect(find.semantics.byLabel('Paste text'), findsWidgets);
    expect(tester.takeException(), isNull);
    semantics.dispose();
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

    await tester.tap(find.text('Paste text'));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('Paste text'));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('Import file'));
    await tester.pumpAndSettle();

    expect(captureSource.calls, 1);
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

    await tester.tap(find.text('Import file'));
    await tester.pump();
    expect(captureSource.calls, 1);

    await tester.tap(find.text('Import file'), warnIfMissed: false);
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

    await tester.tap(find.text('Import file'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('Paste text'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(FTextField),
      'date,description,amount\n2026-05-10,Coffee,-38.50',
    );
    await tester.tap(find.text('Parse'));
    await tester.pumpAndSettle();

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
      containsAll(['entry-draft-2', 'entry-draft-1']),
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

    await tester.tap(find.text('Import file'));
    await tester.pumpAndSettle();
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
