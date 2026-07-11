import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/local_hlc_stamper.dart';

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

/// Builds [MutationStamp]s. Production wiring resolves user / device ids and
/// advances the shared local HLC directly in Drift; tests can supply a fake by
/// overriding [mutationStamperProvider]. Local writes must never wait for sync
/// engine initialization or a historical sync backfill.
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

  /// Generates a fresh HLC tick. Production binding writes through the shared
  /// Drift cursor; tests inject a deterministic stub.
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
  final auth = ref.watch(authStateProvider);

  final String deviceId;
  switch (auth) {
    case AuthLocalOnly():
      deviceId = await ref.read(deviceIdentityStoreProvider).getOrCreate();
    case AuthLoggedIn(:final session):
      deviceId = session.deviceId;
    default:
      return _unauthenticatedMutationStamper();
  }

  final db = await ref.watch(appDatabaseProvider.future);
  final hlcStamper = LocalHlcStamper(db: db, deviceId: deviceId);
  return MutationStamper(
    currentUserId: ref.watch(currentUserIdProvider),
    deviceId: () async => deviceId,
    stampHlc: hlcStamper.stamp,
  );
});

MutationStamper _unauthenticatedMutationStamper() {
  Future<Never> fail() async {
    throw StateError('MutationStamper requires an authenticated session.');
  }

  return MutationStamper(currentUserId: fail, deviceId: fail, stampHlc: fail);
}
