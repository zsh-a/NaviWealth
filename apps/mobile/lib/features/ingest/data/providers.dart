/// §5.10.10 / S5a — Riverpod surface for the Layer 4 ingest pipeline.
///
/// Wiring only. The store is owner-scoped (like `undoStackProvider`),
/// the dedup ledger snapshot is projected from the live expense stream
/// via the shared `expenseToTransactionInput` adapter, and the confirm
/// service reuses the existing `proposalApplierProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/local/skills/skills.dart';
import '../../../core/auth/providers.dart';
import '../../../data/db/providers.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../ai_chat/data/providers.dart';
import '../domain/ingest_models.dart';
import 'ingest_confirm_service.dart';
import 'ingest_draft_store.dart';
import 'ingest_pipeline.dart';

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

/// Dedup ledger snapshot — the device's expense truth, projected into
/// the neutral skill shape. Resolved fresh per ingest run.
final _ledgerSnapshotProvider =
    FutureProvider.autoDispose<List<TransactionInput>>((ref) async {
      final expenses = await ref.watch(journalExpensesStreamProvider.future);
      return expenses.map(expenseToTransactionInput).toList(growable: false);
    });

final ingestConfirmServiceProvider =
    FutureProvider<IngestConfirmService?>((ref) async {
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
    final store = _ref.read(ingestDraftStoreProvider);
    if (store == null) {
      return const IngestResult(
        drafts: <IngestDraft>[],
        rejectedReason: '数据库尚未就绪，请稍后重试',
      );
    }
    final auth = _ref.read(authSessionProvider);
    final ledger = await _ref.read(_ledgerSnapshotProvider.future);
    final pipeline = _ref.read(ingestPipelineProvider);

    final result = pipeline.plan(
      source: source,
      existingLedger: ledger,
      ownerUserId: auth?.userId ?? '',
    );
    if (!result.isRejected && result.drafts.isNotEmpty) {
      await store.putAll(result.drafts);
    }
    return result;
  }
}
