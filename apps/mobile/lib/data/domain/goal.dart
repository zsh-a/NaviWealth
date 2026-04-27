import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'sync_meta.dart';

part 'goal.freezed.dart';

@freezed
class Goal with _$Goal {
  const factory Goal({
    required String id,
    required GoalType type,
    required String name,
    String? currency,
    Decimal? targetAmount,
    DateTime? targetDate,
    String? targetAllocationJson,
    String? note,
    required SyncMeta sync,
  }) = _Goal;
}
