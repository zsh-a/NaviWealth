import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'sync_meta.dart';

part 'expense.freezed.dart';

/// FIR-68 — typed view over an expense journal entry.
///
/// The on-disk representation is a balanced `journal_entries` row with
/// `postings`; this class is the read-side projection that pulls the
/// expense-specific fields into the shape the feature UI needs.
///
/// [amount] is the *positive* magnitude of the spend (e.g. `120.00` for a
/// 120 RMB lunch). In the ledger the expense posting is positive and the
/// asset / cash posting is negative; this model exposes the user-facing
/// spend magnitude.
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
