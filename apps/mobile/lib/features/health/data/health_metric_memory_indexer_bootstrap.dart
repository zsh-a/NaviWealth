part of 'health_metric_memory_indexer.dart';

/// Provider that wires the indexer to the Health metric streams. Gated on
/// `domainOptInsProvider`: when Health is off the indexer is built but does
/// not subscribe, so first-time installs spend zero work.
final healthMetricMemoryIndexerProvider = Provider<HealthMetricMemoryIndexer>((
  ref,
) {
  final indexer = HealthMetricMemoryIndexer();

  Future<void> reindexNow(List<HealthMetric> metrics) async {
    final runtime = await ref.read(memoryRuntimeProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    await indexer.reindex(runtime, metrics, ownerUserId: userId);
  }

  () async {
    final resolved = await ref.read(core_auth.domainOptInsProvider.future);
    if (!resolved.contains(DomainScope.health)) {
      return;
    }
    final repo = await ref.read(healthMetricRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();

    Future<void> queue = Future<void>.value();
    void subscribe(HealthMetricKind kind, int limit) {
      final sub = repo
          .watchRecent(ownerUserId: userId, kind: kind, limit: limit)
          .listen((metrics) {
            queue = queue.then((_) => reindexNow(metrics));
            // ignore: discarded_futures
            queue;
          });
      ref.onDispose(sub.cancel);
    }

    for (final kind in HealthMetricKind.values) {
      if (kind == HealthMetricKind.unknown) continue;
      subscribe(kind, _indexerLimitFor(kind));
    }
  }();

  return indexer;
});

int _indexerLimitFor(HealthMetricKind kind) => switch (kind) {
  HealthMetricKind.sleepSession => 60,
  HealthMetricKind.hrvDaily ||
  HealthMetricKind.rhrDaily ||
  HealthMetricKind.heartRateDaily ||
  HealthMetricKind.respiratoryRateDaily ||
  HealthMetricKind.vo2Max ||
  HealthMetricKind.stressDaily ||
  HealthMetricKind.bodyBatteryDaily => 90,
  HealthMetricKind.workoutSession => 150,
  _ => 120,
};
