import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'sync_meta.dart';

part 'liability.freezed.dart';

@freezed
class Liability with _$Liability {
  const factory Liability({
    required String id,
    required LiabilityType type,
    required String name,
    required Decimal principal,
    required Decimal interestRate,
    required String currency,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? termMonths,
    Decimal? monthlyPayment,
    String? note,
    required SyncMeta sync,
  }) = _Liability;
}
