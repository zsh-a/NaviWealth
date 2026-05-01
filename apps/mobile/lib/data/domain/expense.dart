import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'sync_meta.dart';

part 'expense.freezed.dart';

/// FIR-68 — typed view over a [Transaction] of `type = expense`.
///
/// The on-disk representation is still a single `transactions` row — this
/// class is just the read-side projection that pulls the expense-specific
/// bits out of `expenseMetadataJson` so feature code doesn't have to.
///
/// [amount] is the *positive* magnitude of the spend (e.g. `120.00` for a
/// 120 RMB lunch). The underlying transaction stores it as a negative
/// `quantity` so a naive `SUM(quantity * price)` rolls cash flows up
/// correctly without per-type sign-flipping.
@freezed
abstract class Expense with _$Expense {
  const factory Expense({
    required String id,
    required String accountId,
    required String categoryId,
    required Decimal amount,
    required String currency,
    required DateTime tradeDate,
    @Default(<String>[]) List<String> tags,
    String? note,
    required SyncMeta sync,
  }) = _Expense;
}
