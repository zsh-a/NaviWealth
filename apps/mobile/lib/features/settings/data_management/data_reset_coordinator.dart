import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/data_management/data_management.dart';
import '../../../core/data_management/providers.dart';
import '../../../core/persistence/providers.dart';
import '../../../core/sync/domain_generation.dart';
import '../../../core/sync/drift_sync_storage.dart';
import '../../../core/sync/providers.dart';
import '../../../core/sync/sync_api_client.dart';
import '../../../core/sync/sync_scheduler.dart';

class DataResetCoordinator {
  const DataResetCoordinator({
    required DataManagementService service,
    required SyncApiClient api,
    required DomainGenerationStore generations,
    required SyncScheduler? scheduler,
  }) : _service = service,
       _api = api,
       _generations = generations,
       _scheduler = scheduler;

  final DataManagementService _service;
  final SyncApiClient _api;
  final DomainGenerationStore _generations;
  final SyncScheduler? _scheduler;

  Future<int> resetCurrentDevice(DomainScope scope) async {
    _scheduler?.pause();
    try {
      return await _service.resetLocalDomain(scope);
    } finally {
      _scheduler?.resume();
    }
  }

  Future<({int affected, int generation})> resetEverywhere(
    DomainScope scope,
  ) async {
    _scheduler?.pause();
    try {
      final receipt = await _api.resetDomain(domain: scope.wire);
      final affected = await _service.resetLocalDomain(
        scope,
        requeuePreserved: true,
      );
      await _generations.write(receipt.domain, receipt.generation);
      return (affected: affected, generation: receipt.generation);
    } finally {
      _scheduler?.resume();
    }
  }

  Future<int> resetAllCurrentDevice() async {
    _scheduler?.pause();
    try {
      var affected = 0;
      for (final scope in DomainScope.values) {
        affected += await _service.resetLocalDomain(scope);
      }
      return affected;
    } finally {
      _scheduler?.resume();
    }
  }

  /// Permanently resets every domain generation on the server and mirrors each
  /// successful reset locally. If a network failure interrupts the sequence,
  /// completed domains remain safe: the next sync observes their new generation
  /// and finishes the corresponding local reset.
  Future<({int affected, Map<String, int> generations})>
  resetAllEverywhere() async {
    _scheduler?.pause();
    try {
      var affected = 0;
      final generations = <String, int>{};
      for (final scope in DomainScope.values) {
        final receipt = await _api.resetDomain(domain: scope.wire);
        affected += await _service.resetLocalDomain(
          scope,
          requeuePreserved: true,
        );
        await _generations.write(receipt.domain, receipt.generation);
        generations[receipt.domain] = receipt.generation;
      }
      return (affected: affected, generations: generations);
    } finally {
      _scheduler?.resume();
    }
  }
}

final dataResetCoordinatorProvider = FutureProvider<DataResetCoordinator>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  return DataResetCoordinator(
    service: await ref.watch(dataManagementServiceProvider.future),
    api: ref.watch(syncApiClientProvider),
    generations: DriftDomainGenerationStore(database, ownerUserId: ownerUserId),
    scheduler: await ref.watch(syncSchedulerProvider.future),
  );
});
