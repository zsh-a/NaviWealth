import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/persistence/providers.dart';
import 'securities_catalog_loader.dart';
import 'securities_search_service.dart';

/// Loader bound to the live [AppDatabase]. The first read fires the
/// lazy bundle parse + reload-if-needed pipeline; subsequent reads in
/// the same app session return the same instance.
final securitiesCatalogLoaderProvider = FutureProvider<SecuritiesCatalogLoader>(
  (ref) async {
    final db = await ref.watch(appDatabaseProvider.future);
    return SecuritiesCatalogLoader(db: db);
  },
);

/// One-shot, fire-and-forget catalog ensure. Watch this from any feature
/// that needs the catalog to be present before its first interaction
/// (e.g. the trade-entry picker on the asset side). It's idempotent —
/// the loader compares the bundled version + checksum against the
/// persisted meta and skips the rewrite when they match, so calling it
/// repeatedly is cheap.
final securitiesCatalogReadyProvider =
    FutureProvider<SecuritiesCatalogLoadResult>((ref) async {
      final loader = await ref.watch(securitiesCatalogLoaderProvider.future);
      return loader.load();
    });

/// Read-only search service. Holds no mutable state, so the same
/// instance is reused across the app lifetime; the underlying database
/// connection is what drives reactivity.
final securitiesSearchServiceProvider = FutureProvider<SecuritiesSearchService>(
  (ref) async {
    // Wait for the catalog to be materialised so the first search after a
    // fresh install doesn't return an empty list while the bundle is
    // still loading. The provider is cached, so this waits at most once.
    await ref.watch(securitiesCatalogReadyProvider.future);
    final db = await ref.watch(appDatabaseProvider.future);
    return SecuritiesSearchService(db: db);
  },
);
