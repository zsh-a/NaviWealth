import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/device_identity_store.dart';
import '../../../core/auth/owner_transfer_intent.dart';
import '../../../core/auth/providers.dart';
import '../../../core/auth/token_store.dart';
import 'app_mode_store.dart';

/// The caller must stop exposing an identity when compensation cannot finish.
class IdentityRecoveryRequired implements Exception {
  const IdentityRecoveryRequired();

  @override
  String toString() => 'Identity recovery is required';
}

/// The single writer for session, mode and device snapshots. Owner transfers
/// use [write] inside their journaled SQLite transaction; ordinary session
/// changes use [replace] so failed writes restore the prior identity.
class SessionPersistence {
  const SessionPersistence({
    required this.tokens,
    required this.modes,
    required this.devices,
  });

  final TokenStore tokens;
  final AppModeStore modes;
  final DeviceIdentityStore devices;

  Future<OwnerIdentitySnapshot> read() async => OwnerIdentitySnapshot(
    mode: modes.read().wire,
    session: await tokens.read(),
    deviceId: await devices.getOrCreate(),
  );

  Future<void> write(OwnerIdentitySnapshot identity) async {
    final mode = AppMode.parse(identity.mode);
    if (modes.read() != mode) await modes.write(mode);
    final session = identity.session;
    if (session == null) {
      await tokens.clear();
    } else {
      await tokens.write(session);
    }
    await devices.remember(identity.deviceId);
  }

  Future<void> replace(OwnerIdentitySnapshot identity) async {
    final previous = await read();
    try {
      await write(identity);
    } catch (error, stack) {
      try {
        await write(previous);
      } catch (_) {
        throw const IdentityRecoveryRequired();
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}

final sessionPersistenceProvider = Provider<SessionPersistence>(
  (ref) => SessionPersistence(
    tokens: ref.watch(tokenStoreProvider),
    modes: ref.watch(appModeStoreProvider),
    devices: ref.watch(deviceIdentityStoreProvider),
  ),
);
