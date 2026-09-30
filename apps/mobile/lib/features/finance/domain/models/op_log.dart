import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import 'enums.dart';

part 'op_log.freezed.dart';

/// Legacy DTO for the retained `op_logs` table.
///
/// This is not the active sync wire format. Sync v3 uses `op_outbox` dirty
/// pointers to transmit complete versioned row states with row-level LWW.
/// Its serializer does not replay this model or interpret [patchJson].
@freezed
abstract class OpLog with _$OpLog {
  const factory OpLog({
    required String id,
    required String ownerUserId,
    required String deviceId,
    required Hlc hlc,
    required OpKind op,
    required String entityTable,
    required String entityId,
    String? patchJson,
    DateTime? syncedAt,
  }) = _OpLog;
}
