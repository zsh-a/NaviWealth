import '../../../../core/persistence/domain_enums.dart';
import '../../domain/models/account.dart';
import '../data/ingest_confirm_service.dart';
import '../domain/ingest_models.dart';
import '../domain/minor_unit_amount.dart';

enum IngestReviewFilter { all, ready, likelyDuplicate, duplicate, attention }

enum IngestReviewSort { importOrder, newest, oldest, amount }

/// Immutable UI projection for the ingest review workspace.
///
/// Keeping account fallback and actionable-draft filtering outside the widget
/// makes the review rules independently testable and keeps rebuilds focused on
/// rendering rather than deriving business-facing state.
class IngestReviewViewData {
  IngestReviewViewData._({
    required this.items,
    required this.allItems,
    required this.filterCounts,
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
    String query = '',
    IngestReviewFilter filter = IngestReviewFilter.all,
    IngestReviewSort sort = IngestReviewSort.importOrder,
    Set<String> attentionIds = const {},
  }) {
    final payableAccounts = accounts
        .where((account) => !account.archived)
        .toList(growable: false);
    final effectiveSelectedId =
        payableAccounts.any((account) => account.id == selectedAccountId)
        ? selectedAccountId
        : _defaultAccountId(payableAccounts);
    final allItems = List<IngestReviewItem>.of(items);
    bool canConfirm(IngestReviewItem item) =>
        item.canBatchConfirm &&
        !pendingFinalizeIds.contains(item.draft.draftId);
    final tokens = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    final searched = allItems
        .where((item) {
          final draft = item.draft;
          final parsed = draft.parsed;
          if (tokens.isEmpty) return true;
          final text =
              '${parsed.description} ${parsed.categoryHint ?? ''} '
                      '${draft.originLabel ?? ''} ${parsed.currency} '
                      '${formatAbsoluteMinorUnitAmount(parsed.amountMinor)} '
                      '${parsed.occurredAt.toLocal().toIso8601String().split('T').first}'
                  .toLowerCase();
          return tokens.every(text.contains);
        })
        .toList(growable: false);
    bool matches(IngestReviewItem item, IngestReviewFilter scope) =>
        switch (scope) {
          IngestReviewFilter.all => true,
          IngestReviewFilter.ready => canConfirm(item),
          IngestReviewFilter.likelyDuplicate =>
            item.draft.verdict == DedupVerdict.likelyDuplicate,
          IngestReviewFilter.duplicate =>
            item.draft.verdict == DedupVerdict.duplicate,
          IngestReviewFilter.attention =>
            attentionIds.contains(item.draft.draftId) ||
                pendingFinalizeIds.contains(item.draft.draftId) ||
                item.blocksApply ||
                !item.isOrdinaryPending ||
                item.draft.verdict == DedupVerdict.likelyDuplicate ||
                item.draft.parsed.kind == IngestTransactionKind.transfer ||
                item.draft.parsed.kind == IngestTransactionKind.trade,
        };
    final counts = <IngestReviewFilter, int>{
      for (final scope in IngestReviewFilter.values)
        scope: searched.where((item) => matches(item, scope)).length,
    };
    final filtered = searched.where((item) => matches(item, filter)).toList();
    if (sort != IngestReviewSort.importOrder) {
      final positions = {
        for (var i = 0; i < allItems.length; i++) allItems[i].draft.draftId: i,
      };
      filtered.sort((a, b) {
        final left = a.draft.parsed;
        final right = b.draft.parsed;
        final order = switch (sort) {
          IngestReviewSort.newest => right.occurredAt.compareTo(
            left.occurredAt,
          ),
          IngestReviewSort.oldest => left.occurredAt.compareTo(
            right.occurredAt,
          ),
          IngestReviewSort.amount =>
            left.currency.compareTo(right.currency) != 0
                ? left.currency.compareTo(right.currency)
                : right.amountMinor.abs().compareTo(left.amountMinor.abs()),
          IngestReviewSort.importOrder => 0,
        };
        return order != 0
            ? order
            : positions[a.draft.draftId]!.compareTo(
                positions[b.draft.draftId]!,
              );
      });
    }
    final actionableDrafts = filtered
        .where(
          (item) =>
              item.isOrdinaryPending &&
              !pendingFinalizeIds.contains(item.draft.draftId),
        )
        .map((item) => item.draft)
        .toList(growable: false);
    return IngestReviewViewData._(
      items: List<IngestReviewItem>.unmodifiable(filtered),
      allItems: List<IngestReviewItem>.unmodifiable(allItems),
      filterCounts: Map.unmodifiable(counts),
      payableAccounts: List<Account>.unmodifiable(payableAccounts),
      selectedAccountId: effectiveSelectedId,
      actionableDrafts: List<IngestDraft>.unmodifiable(actionableDrafts),
      freshCount: filtered.where(canConfirm).length,
    );
  }

  final List<IngestReviewItem> items;
  final List<IngestReviewItem> allItems;
  final Map<IngestReviewFilter, int> filterCounts;
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
