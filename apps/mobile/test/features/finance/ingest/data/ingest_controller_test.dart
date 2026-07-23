import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/ai_trace.dart';
import 'package:naviwealth/core/ai/contracts/privacy_mode_provider.dart';
import 'package:naviwealth/core/ai/trace/providers.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_pipeline.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_planning_executor.dart';
import 'package:naviwealth/features/finance/ingest/data/providers.dart';
import 'package:naviwealth/features/finance/ingest/data/vision_ingest_client.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late SharedPreferences prefs;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    db = makeTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer buildContainer({
    VisionIngestClient? visionClient,
    String ownerUserId = 'owner-1',
    String Function()? ownerUserIdReader,
    IngestPlanningExecutor? planningExecutor,
    JournalEntryRepository? journalRepository,
  }) {
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) async => db),
        activeUserIdProvider.overrideWith(
          (_) => ownerUserIdReader?.call() ?? ownerUserId,
        ),
        if (visionClient != null)
          visionIngestClientProvider.overrideWithValue(visionClient),
        if (planningExecutor != null)
          ingestPlanningExecutorProvider.overrideWithValue(planningExecutor),
        if (journalRepository != null)
          journalEntryRepositoryProvider.overrideWith(
            (_) async => journalRepository,
          ),
      ],
    );
  }

  Future<IngestDraftStore> readyStore(ProviderContainer container) async {
    await container.read(appDatabaseProvider.future);
    final store = container.read(ingestDraftStoreProvider);
    expect(store, isNotNull);
    return store!;
  }

  group('IngestController', () {
    test('device CSV path persists drafts for the active owner', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final store = await readyStore(container);

      final result = await container
          .read(ingestControllerProvider)
          .ingest(
            const IngestSource(
              kind: IngestSourceKind.csv,
              payload:
                  'date,description,amount,currency\n'
                  '2026-06-18,Luckin Coffee,-18.00,CNY\n',
              originLabel: 'statement.csv',
            ),
          );

      expect(result.isRejected, isFalse);
      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.ownerUserId, 'owner-1');
      expect(result.drafts.single.originLabel, 'statement.csv');
      expect(result.drafts.single.verdict, DedupVerdict.newTxn);

      final persisted = await store.listByStatus(DraftStatus.pending);
      expect(persisted, hasLength(1));
      expect(persisted.single.draftId, result.drafts.single.draftId);
      expect(persisted.single.parsed.description, 'Luckin Coffee');
      expect(persisted.single.parsed.amountMinor, -1800);
    });

    test('device path dedups re-imports against pending drafts', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final store = await readyStore(container);
      const source = IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            'date,description,amount,currency\n'
            '2026-06-18,Netflix,-68.00,CNY\n',
      );

      final first = await container
          .read(ingestControllerProvider)
          .ingest(source);
      final second = await container
          .read(ingestControllerProvider)
          .ingest(source);

      expect(first.drafts.single.verdict, DedupVerdict.newTxn);
      expect(second.drafts.single.verdict, DedupVerdict.duplicate);
      expect(
        second.drafts.single.dedupTargetEntryId,
        first.drafts.single.draftId,
      );

      final persisted = await store.listByStatus(DraftStatus.pending);
      expect(persisted, hasLength(2));
      expect(
        persisted.map((draft) => draft.draftId),
        containsAll([
          first.drafts.single.draftId,
          second.drafts.single.draftId,
        ]),
      );
    });

    test('device path dedups re-imports against confirming drafts', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final store = await readyStore(container);
      const source = IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            'date,description,amount,currency\n'
            '2026-06-18,Netflix,-68.00,CNY\n',
      );

      final first = await container
          .read(ingestControllerProvider)
          .ingest(source);
      final firstDraft = first.drafts.single;
      final claimed = await store.transition(
        IngestLifecycleTransition(
          ownerUserId: firstDraft.ownerUserId,
          draftId: firstDraft.draftId,
          expectedStatus: DraftStatus.pending,
          expectedRevision: 0,
          nextStatus: DraftStatus.confirming,
          nextOperationToken: 'test-claim',
        ),
      );
      expect(claimed.outcome, IngestLifecycleMutationOutcome.applied);

      final second = await container
          .read(ingestControllerProvider)
          .ingest(source);

      expect(second.drafts.single.verdict, DedupVerdict.duplicate);
      expect(second.drafts.single.dedupTargetEntryId, firstDraft.draftId);
    });

    test(
      'dedup snapshot cannot miss a draft settling during ledger read',
      () async {
        late IngestDraftStore store;
        late IngestDraft firstDraft;
        var ledgerReads = 0;
        final repository = _InterleavingJournalRepository(
          db: db,
          beforeEmit: () async {
            ledgerReads += 1;
            if (ledgerReads != 2) return;
            final claimed = await store.transition(
              IngestLifecycleTransition(
                ownerUserId: firstDraft.ownerUserId,
                draftId: firstDraft.draftId,
                expectedStatus: DraftStatus.pending,
                expectedRevision: firstDraft.revision,
                nextStatus: DraftStatus.confirmed,
              ),
            );
            expect(claimed.outcome, IngestLifecycleMutationOutcome.applied);
          },
        );
        final container = buildContainer(journalRepository: repository);
        addTearDown(container.dispose);
        store = await readyStore(container);
        const source = IngestSource(
          kind: IngestSourceKind.csv,
          payload:
              'date,description,amount,currency\n'
              '2026-06-18,Settling Coffee,-18.00,CNY\n',
        );

        firstDraft =
            (await container.read(ingestControllerProvider).ingest(source))
                .drafts
                .single;
        final second = await container
            .read(ingestControllerProvider)
            .ingest(source);

        expect(second.drafts.single.verdict, DedupVerdict.duplicate);
        expect(second.drafts.single.dedupTargetEntryId, firstDraft.draftId);
      },
    );

    test(
      'concurrent identical imports serialize snapshot through putAll',
      () async {
        final container = buildContainer();
        addTearDown(container.dispose);
        final store = await readyStore(container);
        const source = IngestSource(
          kind: IngestSourceKind.csv,
          payload:
              'date,description,amount,currency\n'
              '2026-06-18,Concurrent Coffee,-18.00,CNY\n',
        );
        final controller = container.read(ingestControllerProvider);

        final results = await Future.wait([
          controller.ingest(source),
          controller.ingest(source),
        ]);

        expect(results.first.drafts.single.verdict, DedupVerdict.newTxn);
        expect(results.last.drafts.single.verdict, DedupVerdict.duplicate);
        expect(
          results.last.drafts.single.dedupTargetEntryId,
          results.first.drafts.single.draftId,
        );
        expect(await store.listByStatus(DraftStatus.pending), hasLength(2));
      },
    );

    test('planning failure releases the FIFO for the next import', () async {
      var calls = 0;
      Future<IngestPlanningAnalysis> executor(
        IngestPlanningRequest request,
      ) async {
        calls++;
        if (calls == 1) throw StateError('worker failed');
        return analyzeIngestPlanning(request);
      }

      final container = buildContainer(planningExecutor: executor);
      addTearDown(container.dispose);
      await readyStore(container);
      const source = IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            'date,description,amount,currency\n'
            '2026-06-18,Queue Recovery,-18.00,CNY\n',
      );
      final controller = container.read(ingestControllerProvider);

      final first = controller.ingest(source);
      final second = controller.ingest(source);

      await expectLater(first, throwsStateError);
      final recovered = await second.timeout(const Duration(seconds: 2));
      expect(recovered.drafts.single.verdict, DedupVerdict.newTxn);
      expect(calls, 2);
    });

    test(
      'blocked Vision parse does not occupy the local planning FIFO',
      () async {
        final vision = _BlockingVisionIngestClient([
          ParsedTransaction(
            description: 'Vision row',
            amountMinor: -4200,
            currency: 'CNY',
            occurredAt: DateTime.utc(2026, 6, 18),
          ),
        ]);
        final container = buildContainer(visionClient: vision);
        addTearDown(container.dispose);
        await readyStore(container);
        final controller = container.read(ingestControllerProvider);

        final visionResult = controller.ingest(
          const IngestSource(
            kind: IngestSourceKind.receiptImage,
            payload: 'base64-image',
            mime: 'image/png',
          ),
        );
        await vision.started.future;

        final csvResult = await controller
            .ingest(
              const IngestSource(
                kind: IngestSourceKind.csv,
                payload:
                    'date,description,amount,currency\n'
                    '2026-06-18,CSV wins,-18.00,CNY\n',
              ),
            )
            .timeout(const Duration(seconds: 2));
        expect(csvResult.drafts.single.verdict, DedupVerdict.newTxn);

        vision.release.complete();
        expect((await visionResult).drafts, hasLength(1));
      },
    );

    test(
      'Vision keeps captured owner and filters another owner ledger',
      () async {
        var activeOwner = 'owner-a';
        final otherOwnerExpense = Expense(
          id: 'owner-b-expense',
          categoryId: 'expense:coffee',
          amount: Decimal.parse('38'),
          currency: 'CNY',
          tradeDate: DateTime.utc(2026, 6, 18),
          note: 'Shared Merchant',
          sync: SyncMeta(
            ownerUserId: 'owner-b',
            updatedAt: DateTime.utc(2026, 6, 18),
            updatedByDevice: 'device-b',
            hlc: Hlc.zero('device-b'),
          ),
        );
        final journal = _StaticExpenseJournalRepository(
          db: db,
          expenses: [otherOwnerExpense],
        );
        final vision = _BlockingVisionIngestClient([
          ParsedTransaction(
            description: 'Shared Merchant',
            amountMinor: -3800,
            currency: 'CNY',
            occurredAt: DateTime.utc(2026, 6, 18),
          ),
        ]);
        final container = buildContainer(
          ownerUserIdReader: () => activeOwner,
          visionClient: vision,
          journalRepository: journal,
        );
        addTearDown(container.dispose);
        final ownerAStore = await readyStore(container);
        final controller = container.read(ingestControllerProvider);

        final resultFuture = controller.ingest(
          const IngestSource(
            kind: IngestSourceKind.receiptImage,
            payload: 'base64-image',
            mime: 'image/png',
          ),
        );
        await vision.started.future;
        activeOwner = 'owner-b';
        container.invalidate(activeUserIdProvider);
        final ownerBStore = container.read(ingestDraftStoreProvider)!;

        vision.release.complete();
        final result = await resultFuture;

        expect(result.drafts.single.ownerUserId, 'owner-a');
        expect(result.drafts.single.verdict, DedupVerdict.newTxn);
        expect(
          await ownerAStore.listByStatus(DraftStatus.pending),
          hasLength(1),
        );
        expect(await ownerBStore.listByStatus(DraftStatus.pending), isEmpty);
      },
    );

    test('privacy gate blocks Vision before touching the client', () async {
      final vision = _RecordingVisionIngestClient(
        parsed: const <ParsedTransaction>[],
      );
      final container = buildContainer(visionClient: vision);
      addTearDown(container.dispose);
      await readyStore(container);
      await container
          .read(aiPrivacySettingsProvider.notifier)
          .setMode(AiPrivacyMode.amountsLocal);

      final result = await container
          .read(ingestControllerProvider)
          .ingest(
            const IngestSource(
              kind: IngestSourceKind.receiptImage,
              payload: 'base64-image',
              mime: 'image/png',
            ),
          );

      expect(result.isRejected, isTrue);
      expect(result.rejectedReason, contains('模型解析'));
      expect(result.drafts, isEmpty);
      expect(vision.calls, 0);
    });

    test('Vision path persists parsed drafts and trace metadata', () async {
      final vision = _RecordingVisionIngestClient(
        parsed: [
          ParsedTransaction(
            description: 'Taxi receipt',
            amountMinor: -4200,
            currency: 'cny',
            occurredAt: DateTime.utc(2026, 6, 18),
            confidence: 0.72,
          ),
        ],
      );
      final container = buildContainer(visionClient: vision);
      addTearDown(container.dispose);
      final store = await readyStore(container);

      final result = await container
          .read(ingestControllerProvider)
          .ingest(
            const IngestSource(
              kind: IngestSourceKind.receiptImage,
              payload: 'base64-image',
              mime: 'image/png',
              originLabel: 'receipt.png',
            ),
          );

      expect(result.isRejected, isFalse);
      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.traceId, isNotNull);
      expect(result.drafts.single.parsed.description, 'Taxi receipt');
      expect(result.drafts.single.parsed.currency, 'cny');
      expect(result.drafts.single.sourceKind, IngestSourceKind.receiptImage);
      expect(vision.calls, 1);
      expect(vision.lastKind, IngestSourceKind.receiptImage);
      expect(vision.lastMime, 'image/png');
      expect(vision.lastContentBase64, 'base64-image');

      final persisted = await store.listByStatus(DraftStatus.pending);
      expect(persisted, hasLength(1));
      expect(persisted.single.traceId, result.drafts.single.traceId);
      expect(persisted.single.originLabel, 'receipt.png');

      final traces = await container.read(aiTraceStoreProvider).recent();
      expect(traces, hasLength(1));
      expect(traces.single.requestId, result.drafts.single.traceId);
      expect(traces.single.backend, Backend.device);
      expect(traces.single.routingReason, kFrbVisionIngestRoutingReason);
      expect(
        traces.single.spans.map((span) => span.name),
        contains('tool:parse_receipt_image'),
      );
    });

    test(
      'returns an actionable rejection while the database is booting',
      () async {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ingestDraftStoreProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);

        final result = await container
            .read(ingestControllerProvider)
            .ingest(
              const IngestSource(
                kind: IngestSourceKind.csv,
                payload:
                    'date,description,amount,currency\n'
                    '2026-06-18,Coffee,-18.00,CNY\n',
              ),
            );

        expect(result.isRejected, isTrue);
        expect(result.rejectedReason, contains('数据库尚未就绪'));
      },
    );
  });
}

final class _RecordingVisionIngestClient implements VisionIngestClient {
  _RecordingVisionIngestClient({required this.parsed});

  final List<ParsedTransaction> parsed;

  int calls = 0;
  IngestSourceKind? lastKind;
  String? lastMime;
  String? lastContentBase64;

  @override
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) async {
    calls += 1;
    lastKind = kind;
    lastMime = mime;
    lastContentBase64 = contentBase64;
    return parsed;
  }
}

final class _BlockingVisionIngestClient implements VisionIngestClient {
  _BlockingVisionIngestClient(this.parsed);

  final List<ParsedTransaction> parsed;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) async {
    started.complete();
    await release.future;
    return parsed;
  }
}

final class _StaticExpenseJournalRepository extends JournalEntryRepository {
  _StaticExpenseJournalRepository({required super.db, required this.expenses})
    : super(
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
        fxRateSource: const IdentityFxRateSource(),
        baseCurrency: 'CNY',
      );

  final List<Expense> expenses;

  @override
  Stream<List<Expense>> watchExpenses(String ownerUserId) =>
      Stream.value(expenses);
}

final class _InterleavingJournalRepository extends JournalEntryRepository {
  _InterleavingJournalRepository({required super.db, required this.beforeEmit})
    : super(
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
        fxRateSource: const IdentityFxRateSource(),
        baseCurrency: 'CNY',
      );

  final Future<void> Function() beforeEmit;

  @override
  Stream<List<Expense>> watchExpenses(String ownerUserId) async* {
    await beforeEmit();
    yield const <Expense>[];
  }
}
