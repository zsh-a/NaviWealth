import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/local_hlc_stamper.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/sync_engine.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';

export 'package:naviwealth/core/auth/current_user.dart'
    show currentUserIdProvider, kLocalOnlyUserId;

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

// `currentUserIdProvider` + `kLocalOnlyUserId` re-exported from
// `core/auth/current_user.dart` — see the export above. The cross-domain
// symbols moved to core so shell tools (Memory Layer / sync) can use
// them without importing `features/finance/`.

final mutationStamperProvider = FutureProvider<MutationStamper>((ref) async {
  final auth = ref.watch(authControllerProvider).value;

  if (auth is AuthLocalOnly) {
    // Local-only mode: build a stamper that doesn't depend on the sync
    // engine. The device id comes from the local install identity (no
    // backend); HLC ticks go straight through DriftCursorStore.
    final db = await ref.watch(appDatabaseProvider.future);
    final deviceId = await ref.read(deviceIdentityStoreProvider).getOrCreate();
    final stamper = LocalHlcStamper(db: db, deviceId: deviceId);
    return MutationStamper(
      currentUserId: ref.watch(currentUserIdProvider),
      deviceId: () async => deviceId,
      stampHlc: stamper.stamp,
    );
  }

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
