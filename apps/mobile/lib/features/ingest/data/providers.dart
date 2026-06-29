/// §5.10.10 / S5a — Riverpod surface for the Layer 4 ingest pipeline.
///
/// Wiring only. The store is owner-scoped (like `undoStackProvider`),
/// the dedup ledger snapshot is projected from the live expense stream
/// via the shared `expenseToTransactionInput` adapter, and the confirm
/// service reuses the existing `proposalApplierProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/ai_tools/expense_to_transaction_input.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:uuid/uuid.dart';

import '../../../app/agent_runtime_llm_bridge.dart';
import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/contracts/ai_span.dart';
import '../../../core/ai/contracts/ai_trace.dart';
import '../../../core/ai/contracts/intent.dart';
import '../../../core/ai/contracts/privacy_mode_provider.dart';
import '../../../core/ai/local/skills/skills.dart';
import '../../../core/ai/trace/ai_trace_builder.dart';
import '../../../core/ai/trace/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/persistence/providers.dart';
import '../domain/ingest_models.dart';
import 'device_ingest_client.dart';
import 'ingest_confirm_service.dart';
import 'ingest_draft_store.dart';
import 'ingest_pipeline.dart';
import 'ingest_privacy_gate.dart';
import 'vision_ingest_client.dart';

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

/// Live pending-draft queue. The Layer 3 ambient card + the review page
/// both watch this.
final pendingIngestDraftsProvider =
    StreamProvider.autoDispose<List<IngestDraft>>((ref) async* {
      final store = ref.watch(ingestDraftStoreProvider);
      if (store == null) {
        yield const <IngestDraft>[];
        return;
      }
      yield* store.watchByStatus(DraftStatus.pending);
    });

final ingestPipelineProvider = Provider<IngestPipeline>(
  (ref) => IngestPipeline(),
);

/// Vision parse runs through the embedded FRB profile-backed LLM bridge when
/// an active device profile is available. The former
/// Vision relay (`/ingest/parse`) was deleted with the backend AI surface,
/// so the non-device slot is the
/// [UnavailableVisionIngestClient] stub: it fails with actionable
/// guidance (configure a key / use CSV) which the controller surfaces
/// as the rejected reason — no dead endpoint, no device→cloud failover.
final visionIngestClientProvider = Provider<VisionIngestClient>((ref) {
  final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
  return RoutingVisionIngestClient(
    fallback: const UnavailableVisionIngestClient(),
    device: llmBridge == null
        ? null
        : FrbVisionIngestClient(llmBridge: llmBridge),
  );
});

/// Dedup ledger snapshot — the device's expense truth, projected into
/// the neutral skill shape. Resolved fresh per ingest run.
final _ledgerSnapshotProvider =
    FutureProvider.autoDispose<List<TransactionInput>>((ref) async {
      final expenses = await ref.watch(journalExpensesStreamProvider.future);
      return expenses.map(expenseToTransactionInput).toList(growable: false);
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
        return _ingestProviderVision(source);
      case IngestGateVerdict.deviceParse:
        return _ingestDevice(source);
    }
  }

  Future<IngestResult> _ingestDevice(IngestSource source) async {
    final store = _ref.read(ingestDraftStoreProvider);
    if (store == null) {
      return const IngestResult(
        drafts: <IngestDraft>[],
        rejectedReason: '数据库尚未就绪，请稍后重试',
      );
    }
    final ownerUserId = _ref.read(activeUserIdProvider) ?? '';
    final ledger = await _dedupLedgerWithPending(store);
    final result = _ref
        .read(ingestPipelineProvider)
        .plan(source: source, existingLedger: ledger, ownerUserId: ownerUserId);
    if (!result.isRejected && result.drafts.isNotEmpty) {
      await store.putAll(result.drafts);
    }
    return result;
  }

  /// §5.10.10 / S5b-vision — the Vision branch. Parse (③) runs through
  /// the FRB-backed native provider path ([FrbVisionIngestClient]) using the
  /// user's own key; ④⑤⑥ stay on-device (same `planFromParsed` the CSV path uses)
  /// so dedup runs against the Drift truth, and a full [AiTrace] is
  /// appended because this *is* a real model round-trip. When no FRB LLM
  /// profile is configured the client surfaces actionable "configure a key"
  /// guidance instead.
  Future<IngestResult> _ingestProviderVision(IngestSource source) async {
    final store = _ref.read(ingestDraftStoreProvider);
    if (store == null) {
      return const IngestResult(
        drafts: <IngestDraft>[],
        rejectedReason: '数据库尚未就绪，请稍后重试',
      );
    }
    final ownerUserId = _ref.read(activeUserIdProvider) ?? '';

    final startedAt = DateTime.now().toUtc();
    final requestId = const Uuid().v4();
    List<ParsedTransaction> parsed;
    try {
      parsed = await _ref
          .read(visionIngestClientProvider)
          .parse(
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

    final ledger = await _dedupLedgerWithPending(store);
    final result = _ref
        .read(ingestPipelineProvider)
        .planFromParsed(
          parsed: parsed,
          source: source,
          existingLedger: ledger,
          ownerUserId: ownerUserId,
          traceId: requestId,
        );
    if (result.drafts.isNotEmpty) {
      await store.putAll(result.drafts);
    }
    await _appendProviderVisionTrace(
      requestId: requestId,
      kind: source.kind,
      startedAt: startedAt,
      rowCount: result.total,
    );
    return result;
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
        routingReason: kDeviceVisionDirectRoutingReason,
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
  ) async {
    final ledger = await _ref.read(_ledgerSnapshotProvider.future);
    final pending = await store.listByStatus(DraftStatus.pending);
    if (pending.isEmpty) return ledger;
    return <TransactionInput>[
      ...ledger,
      for (final d in pending)
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
