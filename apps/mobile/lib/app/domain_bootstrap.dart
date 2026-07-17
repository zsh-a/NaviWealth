/// Eager LifeOS domain bootstraps.
///
/// Concrete providers stay in `features/<domain>/`; this app-level seam only
/// loops [DomainPack] contributions so adding a domain bootstrap stays a
/// registry edit, not another hand-written startup list.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/agents/agent_foreground_scheduler.dart';
import '../core/ai/agents/agent_run_controller.dart';
import '../core/ai/agents/agent_run_store.dart';
import '../core/ai/local/memory/providers.dart' as memory_providers;
import '../core/auth/auth_state.dart';
import '../core/auth/providers.dart' as auth;
import '../core/data_management/providers.dart';
import '../core/lifeos/domain_pack.dart';
import '../core/logging/providers.dart';
import '../core/sync/providers.dart';
import 'domain_composition.dart';

/// Starts Memory Runtime indexers for active domains. When an optional domain
/// is disabled, Riverpod drops its previous indexer watches and their stream
/// subscriptions dispose through the domain-owned provider.
final memoryLayerBootstrapProvider = Provider<void>((ref) {
  domainMemoryBootstraps(ref, ref.watch(activeDomainPacksProvider));
});

/// Mounts background scheduler providers from every registered domain.
///
/// This intentionally uses the full registry rather than only active packs:
/// domain-owned background providers observe opt-in changes themselves so they
/// can register on enable and cancel native work on disable.
final domainBackgroundBootstrapProvider = Provider<void>((ref) {
  // Re-run the pack hooks when authentication changes. Finance price sync,
  // for example, must start after an in-app login even when cold start began
  // logged out. Optional pack hooks continue watching opt-ins so they can
  // cancel already-registered native work when a domain is disabled.
  ref.watch(auth.authStateProvider);
  domainBackgroundBootstraps(ref, ref.watch(domainPackRegistryProvider));
});

/// Auth-gated startup composition mounted after first paint.
///
/// Watching the domain-neutral auth seam fixes the old cold-start-only
/// behaviour: sync, memory indexers, maintenance, and agent catch-up now start
/// after a later login/local-only selection as well.
final authenticatedStartupBootstrapProvider = Provider<void>((ref) {
  final authState = ref.watch(auth.authStateProvider);
  if (authState is! AuthLoggedIn && authState is! AuthLocalOnly) return;

  ref.watch(syncSchedulerBootstrapProvider);
  ref.watch(dataMaintenanceBootstrapProvider);
  ref.watch(memoryRuntimeMaintenanceBootstrapProvider);
  ref.watch(memoryLayerBootstrapProvider);
  ref.watch(agentForegroundSchedulerBootstrapProvider);
});

/// Best-effort derived-vector hygiene. Native model loading remains lazy and
/// happens here only for an authenticated/local-only runtime after first paint.
final memoryRuntimeMaintenanceBootstrapProvider = Provider<void>((ref) {
  unawaited(() async {
    final logger = ref.read(loggerProvider);
    try {
      final runtime = await ref.read(
        memory_providers.memoryRuntimeProvider.future,
      );
      final dropped = await runtime.dropStaleVectors();
      if (dropped > 0) {
        logger.i('Memory Runtime dropped $dropped stale embeddings on boot');
      }
    } on Object catch (error, stackTrace) {
      logger.w(
        'Memory Runtime stale-vector sweep failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }());
});

final agentForegroundSchedulerProvider = Provider<AgentForegroundScheduler>((
  ref,
) {
  final scheduler = AgentForegroundScheduler(
    tick: (now) async {
      final controller = await ref.read(agentRunControllerProvider.future);
      final results = await controller.tick(
        now: now,
        trigger: AgentRunTrigger.catchUp,
      );
      return results.length;
    },
    logger: ref.read(loggerProvider),
  );
  ref.onDispose(scheduler.stop);
  return scheduler;
});

/// Eager bootstrap hook for scheduled-agent foreground catch-up.
final agentForegroundSchedulerBootstrapProvider = Provider<void>((ref) {
  final scheduler = ref.watch(agentForegroundSchedulerProvider);
  scheduler.start();
});
