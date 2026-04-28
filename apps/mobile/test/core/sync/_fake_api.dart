import 'package:naviwealth/core/sync/errors.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/data/domain/hlc.dart';

/// Programmable [SyncApiClient] for SyncEngine tests.
///
/// Captures every push/pull request, lets the test queue scripted responses
/// or exceptions, and offers a default "happy server" mode where pushes
/// echo `accepted = ops.length` and pulls drain a server-side op log.
class FakeSyncApiClient implements SyncApiClient {
  /// Server clock used for stamping `server_now` in fake responses.
  Hlc serverHlc = const Hlc(
    wallMillis: 1_000_000_000_000,
    counter: 0,
    nodeId: Hlc.serverNodeId,
  );

  /// Authoritative ops, ordered ascending by HLC.
  final List<Op> serverOps = [];

  /// FIFO of synthetic responses. When non-empty, takes precedence over
  /// the default behaviour. Each entry is either a Push/Pull/MeResponse
  /// (returned), or a SyncException (thrown). This lets tests script
  /// "fail twice then succeed" patterns.
  final List<Object> programmedResponses = [];

  final List<List<Op>> pushedBatches = [];
  final List<({Hlc since, String deviceId})> pullCalls = [];

  String userId = 'u_test';

  @override
  Future<MeResponse> me() async {
    final next = _consume();
    if (next is MeResponse) return next;
    if (next is SyncException) throw next;
    return MeResponse(
      userId: userId,
      serverNow: DateTime.fromMillisecondsSinceEpoch(
        serverHlc.wallMillis,
        isUtc: true,
      ),
      serverHlc: serverHlc,
    );
  }

  @override
  Future<PushResponse> push({
    required String deviceId,
    required List<Op> ops,
  }) async {
    pushedBatches.add(List.unmodifiable(ops));
    final next = _consume();
    if (next is PushResponse) return next;
    if (next is SyncException) throw next;
    // Default: stamp every op, append to server log, echo accepted.
    Hlc highest = serverHlc;
    for (final op in ops) {
      _bumpServerHlc(at: op.hlc.wallMillis);
      final stamped = op.copyWith(hlc: serverHlc);
      serverOps.add(stamped);
      highest = serverHlc;
    }
    return PushResponse(
      accepted: ops.length,
      rejected: const [],
      serverHlcHigh: highest,
      serverNow: DateTime.fromMillisecondsSinceEpoch(
        highest.wallMillis,
        isUtc: true,
      ),
    );
  }

  @override
  Future<PullResponse> pull({
    required String deviceId,
    required Hlc since,
    int limit = kPullPageMaxOps,
  }) async {
    pullCalls.add((since: since, deviceId: deviceId));
    final next = _consume();
    if (next is PullResponse) return next;
    if (next is SyncException) throw next;
    final filtered =
        serverOps.where((o) => o.hlc > since && o.deviceId != deviceId).toList()
          ..sort((a, b) => a.hlc.compareTo(b.hlc));
    final page = filtered.take(limit).toList();
    final hasMore = filtered.length > limit;
    return PullResponse(
      ops: page,
      serverHlcHigh: serverOps.isEmpty ? serverHlc : serverOps.last.hlc,
      hasMore: hasMore,
      serverNow: DateTime.fromMillisecondsSinceEpoch(
        serverHlc.wallMillis,
        isUtc: true,
      ),
    );
  }

  Object? _consume() {
    if (programmedResponses.isEmpty) return null;
    return programmedResponses.removeAt(0);
  }

  void _bumpServerHlc({required int at}) {
    final wall = at > serverHlc.wallMillis ? at : serverHlc.wallMillis;
    final counter = wall == serverHlc.wallMillis ? serverHlc.counter + 1 : 0;
    serverHlc = Hlc(
      wallMillis: wall,
      counter: counter,
      nodeId: Hlc.serverNodeId,
    );
  }

  /// Helper to seed remote ops authored by another device.
  void seedRemote(Op op) {
    _bumpServerHlc(at: op.hlc.wallMillis);
    serverOps.add(op.copyWith(hlc: serverHlc));
  }
}
