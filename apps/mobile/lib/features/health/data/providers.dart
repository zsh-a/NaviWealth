/// HealthOS Riverpod wiring (`docs/healthos-domain.md` §3, D-2.1).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/providers.dart';
import '../../../core/sync/outbox_provider.dart';
import 'health_metric_repository.dart';

/// Async repository — awaits the database + cross-domain outbox so a
/// shell-only build doesn't crash if Health is opt-in OFF.
final healthMetricRepositoryProvider =
    FutureProvider<HealthMetricRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = await ref.watch(outboxStoreProvider.future);
      return HealthMetricRepository(db: db, outbox: outbox);
    });
