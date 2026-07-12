import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/current_user.dart';
import '../auth/domain_scope.dart';
import '../lifeos/domain_pack.dart';
import '../logging/providers.dart';
import '../persistence/providers.dart';
import '../sync/domain_generation.dart';
import 'data_management.dart';
import 'maintenance.dart';

final dataManagementServiceProvider = FutureProvider<DataManagementService>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  final packs = ref.watch(domainPackRegistryProvider);
  final specs = packs
      .map((pack) => pack.dataManagementSpec)
      .whereType<DomainDataManagementSpec>()
      .toList(growable: false);
  return DataManagementService(
    database: database,
    ownerUserId: ownerUserId,
    specs: specs,
    agentIdsByDomain: <DomainScope, List<String>>{
      for (final pack in packs)
        pack.scope: pack.agentPresentationSpecs
            .map((spec) => spec.agentId)
            .toList(growable: false),
    },
  );
});

final dataManagementDomainResetHandlerProvider =
    FutureProvider<DomainResetHandler>((ref) async {
      final service = await ref.watch(dataManagementServiceProvider.future);
      return _DataManagementDomainResetHandler(service);
    });

class _DataManagementDomainResetHandler implements DomainResetHandler {
  const _DataManagementDomainResetHandler(this._service);

  final DataManagementService _service;

  @override
  Future<void> resetLocalDomain(String domain) async {
    final scope = DomainScope.tryParse(domain);
    if (scope == null) return;
    await _service.resetLocalDomain(scope, requeuePreserved: true);
  }
}

/// Uses the complete build inventory rather than active packs so data left by
/// a disabled optional domain remains visible and maintainable.
final domainDataSnapshotsProvider =
    FutureProvider.autoDispose<List<DomainDataSnapshot>>((ref) async {
      final service = await ref.watch(dataManagementServiceProvider.future);
      return service.inspectAll();
    });

final sharedDataSnapshotProvider =
    FutureProvider.autoDispose<SharedDataSnapshot>((ref) async {
      final service = await ref.watch(dataManagementServiceProvider.future);
      return service.inspectSharedData();
    });

final dataMaintenanceServiceProvider = FutureProvider<DataMaintenanceService>((
  ref,
) async {
  return DataMaintenanceService(
    database: await ref.watch(appDatabaseProvider.future),
    ownerUserId: await ref.watch(currentUserIdProvider)(),
  );
});

final automaticMaintenanceEnabledProvider = FutureProvider<bool>((ref) async {
  final service = await ref.watch(dataMaintenanceServiceProvider.future);
  return service.readAutomaticEnabled();
});

final latestDataMaintenanceRunProvider =
    FutureProvider.autoDispose<DataMaintenanceRun?>((ref) async {
      final service = await ref.watch(dataMaintenanceServiceProvider.future);
      return service.latestRun();
    });

final dataMaintenanceBootstrapProvider = Provider<void>((ref) {
  unawaited(() async {
    try {
      final service = await ref.read(dataMaintenanceServiceProvider.future);
      if (await service.readAutomaticEnabled() &&
          await service.isDue(DateTime.now().toUtc())) {
        await service.runRetention();
        ref.invalidate(latestDataMaintenanceRunProvider);
        ref.invalidate(domainDataSnapshotsProvider);
        ref.invalidate(sharedDataSnapshotProvider);
      }
    } catch (error, stackTrace) {
      ref
          .read(loggerProvider)
          .w(
            'data_maintenance: automatic run failed',
            error: error,
            stackTrace: stackTrace,
          );
    }
  }());
});
