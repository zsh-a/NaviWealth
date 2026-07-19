/// §5.10.10 / S5a — Riverpod surface for the Layer 4 ingest pipeline.
///
/// Wiring only. The store is owner-scoped (like `undoStackProvider`),
/// the dedup ledger snapshot is read directly from the journal repository
/// via the shared `expenseToTransactionInput` adapter, and the confirm
/// service reuses the existing `proposalApplierProvider`.
library;

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/ai_tools/expense_to_transaction_input.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/ai/composition/proposal_applier.dart';
import '../../../../core/ai/contracts/ai_span.dart';
import '../../../../core/ai/contracts/ai_trace.dart';
import '../../../../core/ai/contracts/intent.dart';
import '../../../../core/ai/contracts/privacy_mode_provider.dart';
import '../../../../core/ai/trace/ai_trace_builder.dart';
import '../../../../core/ai/trace/providers.dart';
import '../../../../core/auth/current_user.dart';
import '../../../../core/persistence/providers.dart';
import '../../ai_tools/local_skills/local_skills.dart';
import '../domain/ingest_models.dart';
import 'device_ingest_client.dart';
import 'ingest_confirm_service.dart';
import 'ingest_draft_store.dart';
import 'ingest_llm_client.dart';
import 'ingest_pipeline.dart';
import 'ingest_planning_executor.dart';
import 'ingest_privacy_gate.dart';
import 'vision_ingest_client.dart';

const ingestDatabaseUnavailableReason = '数据库尚未就绪，请稍后重试';

/// Owner-scoped staging store. Null while the DB is mid-boot.
final ingestDraftStoreProvider = Provider<IngestDraftStore?>((ref) {
  final dbAsync = ref.watch(appDatabaseProvider);
  // Scope by the active user id (device-only AI works account-less, so
  // this is [kLocalOnlyUserId] in local-only mode) — never the cloud
  // session, which is null without an account. See current_user.dart.
  final ownerUserId = ref.watch(activeUserIdProvider);
  return dbAsync.when(
    data: (db) {
      final store = IngestDraftStore(db, ownerUserId: ownerUserId);
      ref.onDispose(store.dispose);
      return store;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

/// Live pending queue with any persisted apply-recovery continuation.
final pendingIngestReviewItemsProvider =
    StreamProvider.autoDispose<List<IngestReviewItem>>((ref) async* {
      final store = ref.watch(ingestDraftStoreProvider);
      if (store == null) {
        yield const <IngestReviewItem>[];
        return;
      }
      yield* store.watchPendingReviewItems();
    });

final ingestDraftProgressProvider =
    StreamProvider.autoDispose<IngestDraftProgress>((ref) async* {
      final store = ref.watch(ingestDraftStoreProvider);
      if (store == null) {
        yield const IngestDraftProgress.empty();
        return;
      }
      yield* store.watchProgress();
    });

final ingestPipelineProvider = Provider<IngestPipeline>(
  (ref) => IngestPipeline(),
);

final ingestPlanningExecutorProvider = Provider<IngestPlanningExecutor>(
  (ref) => runIngestPlanning,
);

/// Vision parse runs through the embedded FRB profile-backed LLM bridge when
/// an active device profile is available. The former
/// Vision relay (`/ingest/parse`) was deleted with the backend AI surface,
/// so the non-device slot is the
/// [UnavailableVisionIngestClient] stub: it fails with actionable
/// guidance (configure a key / use CSV) which the controller surfaces
/// as the rejected reason — no dead endpoint, no device→cloud failover.
final visionIngestClientProvider = Provider<VisionIngestClient>((ref) {
  final llmClient = ref.watch(ingestLlmProfileClientProvider);
  return RoutingVisionIngestClient(
    fallback: const UnavailableVisionIngestClient(),
    device: llmClient == null
        ? null
        : FrbVisionIngestClient(llmClient: llmClient),
  );
});

final ingestConfirmServiceProvider = FutureProvider<IngestConfirmService?>((
  ref,
) async {
  final store = ref.watch(ingestDraftStoreProvider);
  if (store == null) return null;
  final applier = await ref.watch(proposalApplierProvider.future);
  return IngestConfirmService(applier: applier, store: store);
});

/// Orchestrates ②–⑥: snapshot the ledger, run the pipeline, persist the
/// pending drafts. Pure planning stays in [IngestPipeline]; this is the
/// thin I/O seam the UI calls.
final ingestControllerProvider = Provider<IngestController>((ref) {
  return IngestController(ref);
});

class IngestController {
  IngestController(this._ref);

  final Ref _ref;
  Future<void> _planningTail = Future<void>.value();

  Future<IngestResult> ingest(IngestSource source) async {
    // §5.10.10 / S5b — privacy gate (隐私门). Image / PDF / email need
    // provider Vision; the §5.10.5 posture decides if that is permitted.
    final mode = _ref.read(aiPrivacySettingsProvider).mode;
    switch (ingestPrivacyGate(source.kind, mode)) {
      case IngestGateVerdict.blockedByPrivacy:
        return const IngestResult(
          drafts: <IngestDraft>[],
          rejectedReason:
              '隐私模式「金额完全本地」已禁用模型解析；'
              '请改用 CSV / 文本粘贴，或在设置中调整 AI 隐私模式',
        );
      case IngestGateVerdict.providerVisionAllowed:
        final context = _captureContext();
        if (context == null) return _databaseUnavailable();
        return _ingestProviderVision(source, context);
      case IngestGateVerdict.deviceParse:
        final context = _captureContext();
        if (context == null) return _databaseUnavailable();
        return _ingestDevice(source, context);
    }
  }

  Future<IngestResult> _ingestDevice(
    IngestSource source,
    _CapturedIngestContext context,
  ) => _enqueuePlanning(
    () => _analyzeAndPersist(
      source: source,
      context: context,
      payload: DeviceIngestPlanningPayload(
        kind: source.kind,
        raw: source.payload,
        defaultCurrency: 'CNY',
      ),
    ),
  );

  /// §5.10.10 / S5b-vision — the Vision branch. Parse (③) runs through
  /// the FRB-backed native provider path ([FrbVisionIngestClient]) using the
  /// user's own key; ④⑤⑥ stay on-device (same `planFromParsed` the CSV path uses)
  /// so dedup runs against the Drift truth, and a full [AiTrace] is
  /// appended because this *is* a real model round-trip. When no FRB LLM
  /// profile is configured the client surfaces actionable "configure a key"
  /// guidance instead.
  Future<IngestResult> _ingestProviderVision(
    IngestSource source,
    _CapturedIngestContext context,
  ) async {
    final startedAt = DateTime.now().toUtc();
    final requestId = const Uuid().v4();
    final visionClient = _ref.read(visionIngestClientProvider);
    List<ParsedTransaction> parsed;
    try {
      parsed = await visionClient.parse(
        kind: source.kind,
        mime: source.mime ?? 'application/octet-stream',
        contentBase64: source.payload,
      );
    } on VisionIngestException catch (e) {
      return IngestResult(
        drafts: const <IngestDraft>[],
        rejectedReason: e.message,
      );
    }

    final result = await _enqueuePlanning(
      () => _analyzeAndPersist(
        source: source,
        context: context,
        payload: PreParsedIngestPlanningPayload(parsed),
        traceId: requestId,
      ),
    );
    await _appendProviderVisionTrace(
      requestId: requestId,
      kind: source.kind,
      startedAt: startedAt,
      rowCount: result.total,
    );
    return result;
  }

  _CapturedIngestContext? _captureContext() {
    final store = _ref.read(ingestDraftStoreProvider);
    if (store == null) return null;
    final ownerUserId = _ref.read(activeUserIdProvider) ?? '';
    if ((store.ownerUserId ?? '') != ownerUserId) return null;
    return _CapturedIngestContext(
      ownerUserId: ownerUserId,
      store: store,
      pipeline: _ref.read(ingestPipelineProvider),
      executor: _ref.read(ingestPlanningExecutorProvider),
    );
  }

  IngestResult _databaseUnavailable() => const IngestResult(
    drafts: <IngestDraft>[],
    rejectedReason: ingestDatabaseUnavailableReason,
  );

  Future<IngestResult> _analyzeAndPersist({
    required IngestSource source,
    required _CapturedIngestContext context,
    required IngestPlanningPayload payload,
    String? traceId,
  }) async {
    context.requireOwnerBinding();
    final ledger = await _dedupLedgerWithPending(
      context.store,
      context.ownerUserId,
    );
    final analysis = await context.executor(
      IngestPlanningRequest(payload: payload, existingLedger: ledger),
    );
    final result = context.pipeline.materialize(
      analysis: analysis,
      source: source,
      ownerUserId: context.ownerUserId,
      traceId: traceId,
    );
    context.requireOwnerBinding();
    if (result.drafts.any(
      (draft) => draft.ownerUserId != context.ownerUserId,
    )) {
      throw StateError('Ingest planning crossed its captured owner boundary.');
    }
    if (!result.isRejected && result.drafts.isNotEmpty) {
      await context.store.putAll(result.drafts);
    }
    return result;
  }

  Future<T> _enqueuePlanning<T>(Future<T> Function() action) {
    final predecessor = _planningTail;
    final release = Completer<void>();
    _planningTail = release.future;
    return () async {
      try {
        await predecessor;
        return await action();
      } finally {
        release.complete();
      }
    }();
  }

  /// Best-effort transparency record — a Vision parse sends content to the
  /// user's configured model provider and must show up in the §5.10.5 audit
  /// surface. Failing to write the trace never fails the ingest.
  Future<void> _appendProviderVisionTrace({
    required String requestId,
    required IngestSourceKind kind,
    required DateTime startedAt,
    required int rowCount,
  }) async {
    try {
      final tier = _ref.read(aiPrivacySettingsProvider).maxBudgetTier;
      final seed = AiTrace(
        requestId: requestId,
        startedAtIso: startedAt.toIso8601String(),
        intent: const IntentHint(
          capability: Capability.classify,
          risk: RiskLevel.info,
          label: 'ingest_vision',
        ),
        backend: Backend.device,
        budgetTier: tier,
        routingReason: kFrbVisionIngestRoutingReason,
        totalDurationMs: 0,
      );
      final parseEnd = DateTime.now().toUtc();
      final trace =
          (AiTraceBuilder.fromSeed(seed)..addSpan(
                id: 'tool:parse',
                kind: AiSpanKind.tool,
                name: 'tool:parse_${visionIngestKindWire(kind)}',
                startedAt: startedAt,
                endedAt: parseEnd,
              ))
              .finalize(finishedAt: parseEnd);
      await _ref.read(aiTraceStoreProvider).append(trace);
    } catch (_) {
      // Transparency is decorative relative to the parse itself.
    }
  }

  Future<List<TransactionInput>> _dedupLedgerWithPending(
    IngestDraftStore store,
    String ownerUserId,
  ) async {
    // Snapshot review work first. If a confirmation completes before the
    // ledger read, the committed row is then visible in the later snapshot;
    // reading in the opposite order could miss it from both sources.
    final reviewDrafts = (await store.listPendingReviewItems())
        .map((item) => item.draft)
        .toList(growable: false);
    final repository = await _ref.read(journalEntryRepositoryProvider.future);
    final expenses = await repository.watchExpenses().first;
    final entries = await repository.watchAllWithPostings().first;
    final ledger = <TransactionInput>[
      ...expenses
          .where((expense) => expense.sync.ownerUserId == ownerUserId)
          .map(expenseToTransactionInput),
      for (final entry in entries)
        if (entry.entry.sync.ownerUserId == ownerUserId)
          ?_incomeTransactionInput(entry),
    ];
    if (reviewDrafts.isEmpty) return ledger;
    return <TransactionInput>[
      ...ledger,
      for (final d in reviewDrafts)
        if (d.ownerUserId == ownerUserId)
          TransactionInput(
            id: d.draftId,
            description: d.parsed.description,
            amountMinor: d.parsed.amountMinor.toString(),
            currency: d.parsed.currency,
            occurredAt: d.parsed.occurredAt,
            categoryId: d.parsed.categoryHint,
          ),
    ];
  }
}

TransactionInput? _incomeTransactionInput(JournalEntryWithPostings entry) {
  for (final posting in entry.postings) {
    if (!posting.accountId.toLowerCase().contains(':income:') ||
        posting.units >= Decimal.zero) {
      continue;
    }
    final minor = (-posting.units * Decimal.fromInt(100))
        .round()
        .toBigInt()
        .toString();
    return TransactionInput(
      id: entry.entry.id,
      description: entry.entry.payee ?? entry.entry.narration,
      amountMinor: minor,
      currency: posting.unit,
      occurredAt: entry.entry.date,
      accountId: posting.accountId,
      categoryId: posting.accountId,
    );
  }
  return null;
}

final class _CapturedIngestContext {
  const _CapturedIngestContext({
    required this.ownerUserId,
    required this.store,
    required this.pipeline,
    required this.executor,
  });

  final String ownerUserId;
  final IngestDraftStore store;
  final IngestPipeline pipeline;
  final IngestPlanningExecutor executor;

  void requireOwnerBinding() {
    if ((store.ownerUserId ?? '') != ownerUserId) {
      throw StateError('Ingest draft store owner binding changed.');
    }
  }
}
