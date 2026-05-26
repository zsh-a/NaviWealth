import 'package:freezed_annotation/freezed_annotation.dart';

import 'hlc.dart';

part 'sync_meta.freezed.dart';

/// Sync metadata embedded in every replicable row.
///
/// Carried as a value object so that domain code can reason about a row's
/// sync state without each entity re-declaring the same five fields. On the
/// Drift side these become five columns on the table — there's no nested
/// struct in SQL — but the in-memory model groups them.
///
/// Field semantics:
///  - [ownerUserId] — partition key for sync. Filters on every read query
///    so multi-account devices never leak data across users.
///  - [updatedAt] — server-authoritative wall time of last write. The
///    client populates it locally on creation and lets the server stomp it
///    on push; it's the human-readable "last modified" only.
///  - [updatedByDevice] — last writer's device id. Used for debugging and
///    for the "edited from `<device>`" UI affordance.
///  - [hlc] — actual conflict-resolution clock; the merge algorithm reads
///    this, **never** [updatedAt].
///  - [deletedAt] — tombstone. Rows are never physically removed; queries
///    filter `deletedAt IS NULL` for the live view, but sync still ships
///    the row so peers learn about the delete.
@freezed
abstract class SyncMeta with _$SyncMeta {
  const factory SyncMeta({
    required String ownerUserId,
    required DateTime updatedAt,
    required String updatedByDevice,
    required Hlc hlc,
    DateTime? deletedAt,
  }) = _SyncMeta;
}
