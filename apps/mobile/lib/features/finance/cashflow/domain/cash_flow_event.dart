import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'cash_flow_kind.dart';

part 'cash_flow_event.freezed.dart';

@freezed
abstract class CashFlowEvent with _$CashFlowEvent {
  const factory CashFlowEvent({
    required String journalEntryId,
    required DateTime date,
    required CashFlowKind kind,

    /// Signed amount in the active base currency. Positive means cash moves
    /// into user asset accounts; negative means cash leaves them.
    required Decimal signedAmount,

    /// Signed amount in [currency], before any base-currency conversion.
    required Decimal originalAmount,
    required String currency,

    /// User asset account whose cash leg best represents this flow.
    required String accountId,
    required AccountSide counterAccountSide,
    String? counterAccountId,
    String? counterAccountName,
    @Default(false) bool isForecast,
  }) = _CashFlowEvent;
}
