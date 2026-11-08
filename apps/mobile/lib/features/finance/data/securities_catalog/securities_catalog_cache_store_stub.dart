import 'securities_catalog_cache_store_base.dart';

/// Web keeps the bundled catalog only: GitHub Release assets carry no CORS
/// headers, and Web deploys already ship the latest committed catalog.
SecuritiesCatalogCacheStore createSecuritiesCatalogCacheStore() =>
    MemorySecuritiesCatalogCacheStore();
