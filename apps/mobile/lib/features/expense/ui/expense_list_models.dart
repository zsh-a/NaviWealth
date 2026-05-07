/// User-selectable bucket size for the expense list.
enum ExpenseGrouping { month, week }

/// In-memory filter applied client-side to the materialised expense list.
class ExpenseFilters {
  const ExpenseFilters({
    this.fromAccountId,
    this.expenseAccountId,
    this.keyword = '',
    this.grouping = ExpenseGrouping.month,
  });

  final String? fromAccountId;
  final String? expenseAccountId;
  final String keyword;
  final ExpenseGrouping grouping;

  bool get isEmpty =>
      fromAccountId == null &&
      expenseAccountId == null &&
      keyword.trim().isEmpty;

  ExpenseFilters copyWith({
    Object? fromAccountId = _sentinel,
    Object? expenseAccountId = _sentinel,
    String? keyword,
    ExpenseGrouping? grouping,
  }) {
    return ExpenseFilters(
      fromAccountId: fromAccountId == _sentinel
          ? this.fromAccountId
          : fromAccountId as String?,
      expenseAccountId: expenseAccountId == _sentinel
          ? this.expenseAccountId
          : expenseAccountId as String?,
      keyword: keyword ?? this.keyword,
      grouping: grouping ?? this.grouping,
    );
  }

  static const Object _sentinel = Object();
}
