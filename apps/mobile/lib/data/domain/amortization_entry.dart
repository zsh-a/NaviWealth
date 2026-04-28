import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'sync_meta.dart';

part 'amortization_entry.freezed.dart';

/// One line of a [Liability]'s amortization schedule. The full schedule is
/// derived from `Liability` fields when missing, but we persist generated
/// rows so the user can edit individual payments (early payoff, skipped
/// month, etc.) and have those edits sync.
@freezed
class AmortizationEntry with _$AmortizationEntry {
  const factory AmortizationEntry({
    required String id,
    required String liabilityId,
    required int periodIndex,
    required DateTime dueDate,
    required Decimal principalPayment,
    required Decimal interestPayment,
    required Decimal remainingBalance,
    DateTime? paidAt,
    required SyncMeta sync,
  }) = _AmortizationEntry;
}
