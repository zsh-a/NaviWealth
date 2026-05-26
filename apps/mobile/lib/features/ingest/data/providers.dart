/// §5.10.10 / S5a — Riverpod surface for the Layer 4 ingest pipeline.
///
/// Wiring only. The store is owner-scoped (like `undoStackProvider`),
/// the dedup ledger snapshot is projected from the live expense stream
/// via the shared `expenseToTransactionInput` adapter, and the confirm
/// service reuses the existing `proposalApplierProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/contracts/ai_span.dart';
import '../../../core/ai/contracts/ai_trace.dart';
import '../../../core/ai/contracts/intent.dart';
import '../../../core/ai/contracts/privacy_mode_provider.dart';
import '../../../core/ai/local/skills/skills.dart';
import '../../../core/ai/runtime/ai_runtime.dart';
import '../../../core/ai/trace/ai_trace_builder.dart';
import '../../../core/ai/trace/providers.dart';
import '../../../core/auth/providers.dart';
import '../../../core/persistence/providers.dart';
import '../../ai_chat/data/providers.dart' show deviceLlmRuntimeProvider;
import '../domain/ingest_models.dart';
import 'cloud_ingest_client.dart';
import 'device_ingest_client.dart';
import 'ingest_confirm_service.dart';
import 'ingest_draft_store.dart';
import 'ingest_pipeline.dart';
import 'ingest_privacy_gate.dart';

/// Owner-scoped staging store. Null while the DB is mid-boot.
final ingestDraftStoreProvider = Provider<IngestDraftStore?>((ref) {
  final dbAsync = ref.watch(appDatabaseProvider);
  final auth = ref.watch(authSessionProvider);
  return dbAsync.when(
    data: (db) {
      final store = IngestDraftStore(db, ownerUserId: auth?.userId);
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

/// §4.6 W-D7 — Vision parse runs device-direct when the on-device
/// runtime is available (native incl. desktop × user key × opt-in),
/// reusing the *same* [AnthropicClient] the chat path built. The cloud
/// Vision relay (`/ingest/parse`) was deleted with the rest of the
/// cloud AI backend, so the non-device slot is the
/// [UnavailableCloudIngestClient] stub: it fails with actionable
/// guidance (configure a key / use CSV) which the controller surfaces
/// as the rejected reason — no dead endpoint, no device→cloud failover.
final cloudIngestClientProvider = Provider<CloudIngestClient>((ref) {
  final DeviceLlmRuntime? runtime = ref.watch(deviceLlmRuntimeProvider);
  return RoutingCloudIngestClient(
    cloud: const UnavailableCloudIngestClient(),
    device: runtime == null
        ? null
        : DeviceVisionIngestClient(client: runtime.client),
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
    // cloud Vision; the §5.10.5 posture decides if that is permitted.
    final mode = _ref.read(aiPrivacySettingsProvider).mode;
    switch (ingestPrivacyGate(source.kind, mode)) {
      case IngestGateVerdict.blockedByPrivacy:
        return const IngestResult(
          drafts: <IngestDraft>[],
          rejectedReason:
              '隐私模式「金额完全本地」已禁用云端解析；'
              '请改用 CSV / 文本粘贴，或在设置中调整 AI 隐私模式',
        );
      case IngestGateVerdict.cloudAllowed:
        return _ingestCloud(source);
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
    final auth = _ref.read(authSessionProvider);
    final ledger = await _ref.read(_ledgerSnapshotProvider.future);
    final result = _ref
        .read(ingestPipelineProvider)
        .plan(
          source: source,
          existingLedger: ledger,
          ownerUserId: auth?.userId ?? '',
        );
    if (!result.isRejected && result.drafts.isNotEmpty) {
      await store.putAll(result.drafts);
    }
    return result;
  }

  /// §5.10.10 / S5b-vision — the cloud branch. Backend does ③ (Vision
  /// parse); ④⑤⑥ stay on-device (same `planFromParsed` the CSV path
  /// uses) so dedup runs against the Drift truth, and a full [AiTrace]
  /// is appended because this *is* a real cloud model round-trip.
  Future<IngestResult> _ingestCloud(IngestSource source) async {
    final store = _ref.read(ingestDraftStoreProvider);
    if (store == null) {
      return const IngestResult(
        drafts: <IngestDraft>[],
        rejectedReason: '数据库尚未就绪，请稍后重试',
      );
    }
    final session = _ref.read(authSessionProvider);
    if (session == null) {
      return const IngestResult(
        drafts: <IngestDraft>[],
        rejectedReason: '需要登录后才能使用云端解析',
      );
    }

    final startedAt = DateTime.now().toUtc();
    final requestId = const Uuid().v4();
    List<ParsedTransaction> parsed;
    try {
      parsed = await _ref
          .read(cloudIngestClientProvider)
          .parse(
            session: session,
            kind: source.kind,
            mime: source.mime ?? 'application/octet-stream',
            contentBase64: source.payload,
          );
    } on CloudIngestException catch (e) {
      return IngestResult(
        drafts: const <IngestDraft>[],
        rejectedReason: e.message,
      );
    }

    final ledger = await _ref.read(_ledgerSnapshotProvider.future);
    final result = _ref
        .read(ingestPipelineProvider)
        .planFromParsed(
          parsed: parsed,
          source: source,
          existingLedger: ledger,
          ownerUserId: session.userId,
          traceId: requestId,
        );
    if (result.drafts.isNotEmpty) {
      await store.putAll(result.drafts);
    }
    await _appendCloudTrace(
      requestId: requestId,
      kind: source.kind,
      startedAt: startedAt,
      rowCount: result.total,
    );
    return result;
  }

  /// Best-effort transparency record — a Vision parse is a cloud model
  /// call and must show up in the §5.10.5 audit surface. Failing to
  /// write the trace never fails the ingest.
  Future<void> _appendCloudTrace({
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
        backend: Backend.cloud,
        budgetTier: tier,
        routingReason: 'layer4_cloud_vision',
        totalDurationMs: 0,
      );
      final parseEnd = DateTime.now().toUtc();
      final trace =
          (AiTraceBuilder.fromSeed(seed)..addSpan(
                id: 'tool:parse',
                kind: AiSpanKind.tool,
                name: 'tool:parse_${cloudIngestKindWire(kind)}',
                startedAt: startedAt,
                endedAt: parseEnd,
              ))
              .finalize(finishedAt: parseEnd);
      await _ref.read(aiTraceStoreProvider).append(trace);
    } catch (_) {
      // Transparency is decorative relative to the parse itself.
    }
  }
}
