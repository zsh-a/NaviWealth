import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import 'enums.dart';

part 'liability.freezed.dart';

/// A debt account owned by the user. The amortization schedule is *derived*
/// from these fields by `AmortizationCalculator` rather than stored — see
/// [AmortizationEntry] for the override mechanism that lets users edit a
/// single payment row.
@freezed
abstract class Liability with _$Liability {
  const factory Liability({
    required String id,
    required LiabilityType type,
    required String name,
    required Decimal principal,

    /// Effective annual interest rate as a fraction (e.g. `0.0485` for
    /// 4.85%). For [LiabilityRateType.lprFloating] this is the rate at the
    /// time of last update; the UI should mark it as floating.
    required Decimal interestRate,
    required String currency,
    @Default(RepaymentMethod.equalInstallment) RepaymentMethod paymentMethod,
    @Default(LiabilityRateType.fixed) LiabilityRateType rateType,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? termMonths,
    Decimal? monthlyPayment,

    /// Day of month for credit-card statement closure (信用卡账单日). Used by
    /// the optional reminder feature; ignored for installment loans.
    int? statementDay,

    /// Day of month for credit-card payment due (信用卡还款日).
    int? paymentDueDay,
    String? note,
    required SyncMeta sync,
  }) = _Liability;
}
