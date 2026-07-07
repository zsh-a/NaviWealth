/// Eager LifeOS domain bootstraps.
///
/// Concrete providers stay in `features/<domain>/`; this app-level seam only
/// loops [DomainPack] contributions so adding a domain bootstrap stays a
/// registry edit, not another hand-written startup list.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/agents/agent_foreground_scheduler.dart';
import '../core/ai/agents/agent_run_controller.dart';
import '../core/ai/agents/agent_run_store.dart';
import '../core/lifeos/domain_pack.dart';
import '../core/logging/providers.dart';
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
  domainBackgroundBootstraps(ref, ref.watch(domainPackRegistryProvider));
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
