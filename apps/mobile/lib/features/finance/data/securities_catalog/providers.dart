import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';

import 'securities_catalog_cache_store.dart';
import 'securities_catalog_loader.dart';
import 'securities_catalog_remote.dart';
import 'securities_search_service.dart';

/// Loader bound to the live [AppDatabase]. The first read fires the
/// lazy bundle parse + reload-if-needed pipeline; subsequent reads in
/// the same app session return the same instance.
final securitiesCatalogLoaderProvider = FutureProvider<SecuritiesCatalogLoader>(
  (ref) async {
    final db = await ref.watch(appDatabaseProvider.future);
    return SecuritiesCatalogLoader(
      db: db,
      cacheStore: ref.watch(securitiesCatalogCacheStoreProvider),
      logger: ref.watch(loggerProvider),
    );
  },
);

/// Holds catalogs downloaded from the `securities-catalog` GitHub Release.
final securitiesCatalogCacheStoreProvider =
    Provider<SecuritiesCatalogCacheStore>(
      (ref) => createSecuritiesCatalogCacheStore(),
    );

/// Best-effort out-of-band catalog refresh, mounted by the Finance background
/// bootstrap. No-op on Web and in builds without a manifest URL; otherwise it
/// waits for the bundled catalog, then checks the manifest at most daily.
final securitiesCatalogRemoteRefreshProvider =
    FutureProvider<SecuritiesCatalogRemoteResult>((ref) async {
      final url = ref.watch(appConfigProvider).securitiesCatalogManifestUrl;
      final manifestUrl = Uri.tryParse(url.trim());
      if (kIsWeb || manifestUrl == null || !manifestUrl.hasScheme) {
        return const SecuritiesCatalogRemoteResult(
          SecuritiesCatalogRemoteStatus.disabled,
        );
      }
      // Stay out of cold-start I/O; the catalog is not needed for first paint.
      await Future<void>.delayed(const Duration(seconds: 20));
      await ref.read(securitiesCatalogReadyProvider.future);
      final loader = await ref.read(securitiesCatalogLoaderProvider.future);
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      try {
        return await SecuritiesCatalogRemoteUpdater(
          manifestUrl: manifestUrl,
          dio: dio,
          store: ref.read(securitiesCatalogCacheStoreProvider),
          loader: loader,
          logger: ref.read(loggerProvider),
        ).refresh();
      } finally {
        dio.close(force: true);
      }
    });

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
