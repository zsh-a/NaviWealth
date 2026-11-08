/// Device-local storage for a securities catalog downloaded out of band.
///
/// The cached file uses the same NDJSON format as the bundled asset. It is
/// derived, read-only reference data: never synced and safe to delete, in
/// which case the loader falls back to the catalog bundled in the app.
abstract interface class SecuritiesCatalogCacheStore {
  /// Raw NDJSON of the downloaded catalog, or null when none is cached.
  Future<String?> read();

  /// Atomically replaces the cached catalog.
  Future<void> write(String raw);

  /// Drops the cached catalog (stale or corrupt).
  Future<void> delete();

  /// When the remote manifest was last fetched successfully.
  Future<DateTime?> lastCheckedAt();

  Future<void> markChecked(DateTime at);
}

/// In-memory store for tests and platforms without a writable filesystem.
final class MemorySecuritiesCatalogCacheStore
    implements SecuritiesCatalogCacheStore {
  MemorySecuritiesCatalogCacheStore({this.raw, this.checkedAt});

  String? raw;
  DateTime? checkedAt;

  @override
  Future<String?> read() async => raw;

  @override
  Future<void> write(String value) async => raw = value;

  @override
  Future<void> delete() async => raw = null;

  @override
  Future<DateTime?> lastCheckedAt() async => checkedAt;

  @override
  Future<void> markChecked(DateTime at) async => checkedAt = at;
}
