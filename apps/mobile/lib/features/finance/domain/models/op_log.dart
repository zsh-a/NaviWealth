import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import 'enums.dart';

part 'op_log.freezed.dart';

/// Append-only operation log.
///
/// The OpLog is the wire format for sync: every mutation to a synced table
/// produces one entry, which is shipped to the server and replayed on
/// other devices. Replaying ops in HLC order yields a deterministic state.
///
/// `patchJson` carries only the changed fields, enabling field-level LWW —
/// e.g. two devices editing different attributes of the same transaction
/// won't clobber each other; only the field with the higher HLC wins.
/// `null` patch means a delete (entity-level tombstone).
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
