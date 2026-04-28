import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/repositories/mutation_context.dart';

/// Deterministic [MutationStamper] for tests. Wall-millis is incremented
/// by one on every call so HLC ordering is stable and counter logic is
/// exercised without wiring a real [SyncEngine].
MutationStamper makeStubStamper({
  String userId = 'u-test',
  String deviceId = 'dev-test',
  int initialMillis = 1_700_000_000_000,
}) {
  var millis = initialMillis;
  Hlc? last;
  return MutationStamper(
    currentUserId: () async => userId,
    deviceId: () async => deviceId,
    stampHlc: () async {
      final base = Hlc(wallMillis: millis, counter: 0, nodeId: deviceId);
      final next = last == null
          ? base
          : Hlc.tick(lastSeen: last!, nowMillis: millis);
      last = next;
      millis += 1;
      return next;
    },
  );
}
