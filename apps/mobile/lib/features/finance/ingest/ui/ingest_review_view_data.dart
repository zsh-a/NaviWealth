import '../../../../core/persistence/domain_enums.dart';
import '../../domain/models/account.dart';
import '../data/ingest_confirm_service.dart';
import '../domain/ingest_models.dart';

/// Immutable UI projection for the ingest review workspace.
///
/// Keeping account fallback and actionable-draft filtering outside the widget
/// makes the review rules independently testable and keeps rebuilds focused on
/// rendering rather than deriving business-facing state.
class IngestReviewViewData {
  IngestReviewViewData._({
    required this.items,
    required this.payableAccounts,
    required this.selectedAccountId,
    required this.actionableDrafts,
    required this.freshCount,
  });

  factory IngestReviewViewData.from({
    required List<Account> accounts,
    required List<IngestReviewItem> items,
    required String? selectedAccountId,
    required Set<String> pendingFinalizeIds,
  }) {
    final payableAccounts = accounts
        .where((account) => !account.archived)
        .toList(growable: false);
    final effectiveSelectedId =
        payableAccounts.any((account) => account.id == selectedAccountId)
        ? selectedAccountId
        : _defaultAccountId(payableAccounts);
    final actionableDrafts = items
        .where(
          (item) =>
              item.isOrdinaryPending &&
              !pendingFinalizeIds.contains(item.draft.draftId),
        )
        .map((item) => item.draft)
        .toList(growable: false);
    return IngestReviewViewData._(
      items: List<IngestReviewItem>.unmodifiable(items),
      payableAccounts: List<Account>.unmodifiable(payableAccounts),
      selectedAccountId: effectiveSelectedId,
      actionableDrafts: List<IngestDraft>.unmodifiable(actionableDrafts),
      freshCount: actionableDrafts
          .where((draft) => draft.verdict == DedupVerdict.newTxn)
          .length,
    );
  }

  final List<IngestReviewItem> items;
  final List<Account> payableAccounts;
  final String? selectedAccountId;
  final List<IngestDraft> actionableDrafts;
  final int freshCount;
}

String? _defaultAccountId(List<Account> accounts) {
  if (accounts.isEmpty) return null;
  for (final category in const [AccountCategory.cash, AccountCategory.bank]) {
    for (final account in accounts) {
      if (account.type == category) return account.id;
    }
  }
  return accounts.first.id;
}
