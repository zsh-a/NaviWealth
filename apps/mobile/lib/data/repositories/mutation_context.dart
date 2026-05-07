import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/sync/providers.dart';
import '../../core/sync/sync_engine.dart';
import '../domain/hlc.dart';

/// Per-mutation envelope of sync metadata.
///
/// Repositories take one of these on every write so the sync columns
/// (`owner_user_id`, `updated_at`, `updated_by_device`, `hlc`) and the
/// outbox `Op` are produced from one consistent stamp — generating the
/// HLC and the `updatedAt` separately would let them drift across the
/// row vs. the queued op, which is a confusing class of bug.
class MutationStamp {
  const MutationStamp({
    required this.ownerUserId,
    required this.deviceId,
    required this.hlc,
    required this.now,
  });

  final String ownerUserId;
  final String deviceId;
  final Hlc hlc;
  final DateTime now;
}

/// Builds [MutationStamp]s. Production wiring resolves user / device ids
/// and asks the [SyncEngine] for a fresh HLC tick; tests can supply a
/// fake by overriding [mutationStamperProvider].
class MutationStamper {
  MutationStamper({
    required this.currentUserId,
    required this.deviceId,
    required this.stampHlc,
  });

  /// Resolves the user id for the active session.
  final Future<String> Function() currentUserId;

  /// Resolves the backend-issued device id bound to the active session.
  final Future<String> Function() deviceId;

  /// Generates a fresh HLC tick. Production binding delegates to
  /// `SyncEngine.stampHlc`; tests inject a deterministic stub.
  final Future<Hlc> Function() stampHlc;

  Future<MutationStamp> stamp() async {
    final user = await currentUserId();
    final device = await deviceId();
    final hlc = await stampHlc();
    final wall = DateTime.fromMillisecondsSinceEpoch(
      hlc.wallMillis,
      isUtc: true,
    );
    return MutationStamp(
      ownerUserId: user,
      deviceId: device,
      hlc: hlc,
      now: wall,
    );
  }
}

/// Override in tests to inject a fixed user id.
final currentUserIdProvider = Provider<Future<String> Function()>((ref) {
  final session = ref.watch(authSessionProvider);
  return () async {
    if (session == null) {
      throw StateError('MutationStamper requires an authenticated session.');
    }
    return session.userId;
  };
});

final mutationStamperProvider = FutureProvider<MutationStamper>((ref) async {
  final engine = await ref.watch(syncEngineProvider.future);
  if (engine == null) {
    throw StateError('MutationStamper requires an authenticated session.');
  }
  final session = ref.watch(authSessionProvider);
  final user = ref.watch(currentUserIdProvider);
  return MutationStamper(
    currentUserId: user,
    deviceId: () async {
      if (session == null) {
        throw StateError('MutationStamper requires an authenticated session.');
      }
      return session.deviceId;
    },
    stampHlc: engine.stampHlc,
  );
});
