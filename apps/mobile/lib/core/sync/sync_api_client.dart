import '../../data/domain/hlc.dart';
import 'op.dart';

/// Sync wire-protocol version this client speaks
/// (`docs/sync-protocol.md` §10).
const int kSyncProtocolVersion = 1;

/// Hard ceiling per push batch (§5.2).
const int kPushBatchMaxOps = 500;
const int kPushBatchMaxBytes = 1024 * 1024;

/// Pull page limit (§5.3).
const int kPullPageMaxOps = 500;

/// `GET /me` response.
class MeResponse {
  const MeResponse({
    required this.userId,
    required this.serverNow,
    required this.serverHlc,
  });

  final String userId;
  final DateTime serverNow;
  final Hlc serverHlc;
}

/// Per-op rejection in a push response.
class PushRejection {
  const PushRejection({required this.opId, required this.code, this.message});
  final String opId;
  final String code;
  final String? message;
}

/// `POST /sync/push` response.
class PushResponse {
  const PushResponse({
    required this.accepted,
    required this.rejected,
    required this.serverHlcHigh,
    required this.serverNow,
  });

  final int accepted;
  final List<PushRejection> rejected;

  /// Highest server-stamped HLC in the batch. Used to advance the local
  /// HLC state via `merge()` (§5.2).
  final Hlc serverHlcHigh;
  final DateTime serverNow;
}

/// `GET /sync/pull` response.
class PullResponse {
  const PullResponse({
    required this.ops,
    required this.serverHlcHigh,
    required this.hasMore,
    required this.serverNow,
  });

  final List<Op> ops;

  /// Highest HLC observed on the server (not necessarily the last in this
  /// page). Clients persist this even when [ops] is empty (SP-D-5).
  final Hlc serverHlcHigh;
  final bool hasMore;
  final DateTime serverNow;
}

abstract class SyncApiClient {
  Future<MeResponse> me();

  Future<PushResponse> push({required String deviceId, required List<Op> ops});

  Future<PullResponse> pull({
    required String deviceId,
    required Hlc since,
    int limit = kPullPageMaxOps,
  });
}
