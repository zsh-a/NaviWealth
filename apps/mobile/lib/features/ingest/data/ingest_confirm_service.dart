/// §5.10.10 / S5a step ⑦ — confirmation.
///
/// A confirmed draft is turned into a `ProposalKind.expense`
/// [ReadyProposalPlan] and pushed through the **existing**
/// [ProposalApplier]. That is the whole point: ingest reuses the one
/// audited write path (repository → Drift → OpLog → AiTouch) instead of
/// inventing a parallel one, and the AI is never the final writer —
/// the user's tap is (§5.10.6). Only after the apply succeeds is the
/// draft marked `confirmed`; a failed apply leaves it `pending` so the
/// user can retry or edit.
library;

import 'package:decimal/decimal.dart';

import '../../ai_chat/data/proposal_applier.dart';
import '../../ai_chat/domain/proposal_apply_state.dart';
import '../../ai_chat/domain/proposal_plan.dart';
import '../domain/ingest_models.dart';
import 'ingest_draft_store.dart';

class IngestConfirmException implements Exception {
  IngestConfirmException(this.message);
  final String message;
  @override
  String toString() => 'IngestConfirmException: $message';
}

class IngestConfirmService {
  IngestConfirmService({required this.applier, required this.store});

  final ProposalApplier applier;
  final IngestDraftStore store;

  /// Apply [draft] as an expense paid from [fromAccountId]. Returns the
  /// created journal entry id. Throws [IngestConfirmException] on failure
  /// (the draft stays pending).
  Future<String> confirm(
    IngestDraft draft, {
    required String fromAccountId,
  }) async {
    if (fromAccountId.isEmpty) {
      throw IngestConfirmException('未选择支出账户');
    }
    final plan = expensePlanFor(draft, fromAccountId: fromAccountId);

    final ProposalApplyState state;
    try {
      state = await applier.apply(plan);
    } on ProposalApplyException catch (e) {
      throw IngestConfirmException(e.message);
    }
    if (state.status != ProposalApplyStatus.applied ||
        state.appliedEntityId == null) {
      throw IngestConfirmException(state.errorMessage ?? '写入未完成');
    }
    await store.updateStatus(draft.draftId, DraftStatus.confirmed);
    return state.appliedEntityId!;
  }

  /// Drop [draft] from the queue without writing anything.
  Future<void> dismiss(IngestDraft draft) =>
      store.updateStatus(draft.draftId, DraftStatus.dismissed);

  /// Confirm every still-pending, non-duplicate draft. Duplicates are
  /// left for the user to decide on explicitly. Returns the count
  /// applied; the first failure aborts and rethrows.
  Future<int> confirmAllFresh(
    List<IngestDraft> drafts, {
    required String fromAccountId,
  }) async {
    var applied = 0;
    for (final d in drafts) {
      if (d.status != DraftStatus.pending) continue;
      if (d.verdict != DedupVerdict.newTxn) continue;
      await confirm(d, fromAccountId: fromAccountId);
      applied++;
    }
    return applied;
  }

  /// Pure mapping draft → `propose_expense`-shaped plan. Extracted so
  /// the wire contract with [ProposalApplier] can be unit-tested without
  /// spinning up every repository.
  static ReadyProposalPlan expensePlanFor(
    IngestDraft draft, {
    required String fromAccountId,
  }) {
    final amount = _minorToDecimalString(draft.parsed.amountMinor.abs());
    return ReadyProposalPlan(
      proposalId: draft.draftId,
      kind: ProposalKind.expense,
      summaryZh:
          '记录支出 ${_shortDesc(draft.parsed.description)} '
          '${draft.parsed.currency} $amount',
      payload: <String, Object?>{
        'account_id': fromAccountId,
        'amount': amount,
        'currency': draft.parsed.currency,
        'date': draft.parsed.occurredAt.toUtc().toIso8601String(),
        'note': draft.parsed.description,
        'category': draft.parsed.categoryHint ?? 'other',
      },
    );
  }

  static String _minorToDecimalString(int absMinor) {
    final whole = absMinor ~/ 100;
    final frac = (absMinor % 100).toString().padLeft(2, '0');
    // Round-trips through Decimal exactly; ProposalApplier re-parses it.
    return Decimal.parse('$whole.$frac').toString();
  }

  static String _shortDesc(String s) =>
      s.length <= 24 ? s : '${s.substring(0, 23)}…';
}
