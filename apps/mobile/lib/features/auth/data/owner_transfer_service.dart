import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/owner_transfer_intent.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/providers.dart';
import '../../../core/persistence/owner_data_migration.dart';
import '../../../core/persistence/providers.dart';
import '../../../core/sync/providers.dart' show syncSchedulerProvider;
import '../../../core/sync/sync_scheduler.dart';
import 'session_persistence.dart';

/// Owns the secure write-ahead journal, SQLite commit decision and Sync drain.
/// Called within the controller's serialized session commit boundary.
class OwnerTransferService {
  const OwnerTransferService({
    required this.persistence,
    required this.loadMigration,
    required this.loadScheduler,
    required this.logger,
  });

  final SessionPersistence persistence;
  final Future<OwnerDataMigration> Function() loadMigration;
  final Future<SyncScheduler?> Function() loadScheduler;
  final AppLogger logger;

  /// Runs before the controller exposes any session or mode at startup.
  Future<bool> recoverPending() async {
    final intent = await persistence.tokens.readOwnerTransfer();
    if (intent == null) return false;
    final migration = await loadMigration();
    final committed = await migration.didCommit(intent.id);
    await persistence.write(committed ? intent.target : intent.previous);
    await _finish(intent, migration);
    return true;
  }

  Future<void> transfer({
    required String from,
    required String to,
    required OwnerIdentitySnapshot target,
  }) async {
    if (await persistence.tokens.readOwnerTransfer() != null) {
      throw const IdentityRecoveryRequired();
    }
    final previous = await persistence.read();
    final migration = await loadMigration();
    final scheduler = await loadScheduler();
    final intent = OwnerTransferIntent(
      id: const Uuid().v4(),
      from: from,
      to: to,
      previous: previous,
      target: target,
    );
    var transferred = 0;
    try {
      await scheduler?.pauseAndDrain();
      await persistence.tokens.writeOwnerTransfer(intent);
      transferred = await migration.transfer(
        from: from,
        to: to,
        transferId: intent.id,
        commitIdentity: () => persistence.write(target),
      );
      await _finish(intent, migration);
    } catch (error, stack) {
      bool committed;
      try {
        committed = await migration.didCommit(intent.id);
        await persistence.write(committed ? target : previous);
        await _finish(intent, migration);
      } catch (_) {
        scheduler?.stop();
        throw const IdentityRecoveryRequired();
      }
      if (!committed) {
        scheduler?.resume();
        Error.throwWithStackTrace(error, stack);
      }
    }
    scheduler?.stop();
    logger.event(
      'core.auth.owner_transfer.completed',
      fields: {'row_count': transferred},
    );
  }

  Future<void> _finish(
    OwnerTransferIntent intent,
    OwnerDataMigration migration,
  ) async {
    await persistence.tokens.clearOwnerTransfer();
    try {
      await migration.clearCommitMarker(intent.id);
    } catch (_) {
      // One orphan UUID is harmless and is replaced by the next transfer.
      logger.event('core.auth.owner_transfer.cleanup_deferred');
    }
  }
}

final ownerTransferServiceProvider = Provider<OwnerTransferService>(
  (ref) => OwnerTransferService(
    persistence: ref.watch(sessionPersistenceProvider),
    loadMigration: () async =>
        OwnerDataMigration(await ref.read(appDatabaseProvider.future)),
    loadScheduler: () => ref.read(syncSchedulerProvider.future),
    logger: ref.watch(loggerProvider),
  ),
);
