/// HealthOS Riverpod wiring (`docs/healthos-domain.md` §3, D-2.1).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/providers.dart';
import '../../../core/sync/drift_sync_storage.dart';
import 'health_metric_repository.dart';

/// Async repository — awaits the database so a shell-only build
/// doesn't crash if Health is opt-in OFF.
///
/// We build a local [DriftOutboxStore] here rather than reusing the
/// Finance-side `outboxStoreProvider` (which lives under
/// `features/finance/data/repositories/`) so Health doesn't take a
/// cross-feature dependency on Finance for what is really shared
/// sync machinery. A future D-1.x cleanup will move the outbox
/// provider to `core/sync/`; until then constructing one per domain
/// is cheap (same singleton DB underneath).
final healthMetricRepositoryProvider =
    FutureProvider<HealthMetricRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = DriftOutboxStore(db);
      return HealthMetricRepository(db: db, outbox: outbox);
    });
