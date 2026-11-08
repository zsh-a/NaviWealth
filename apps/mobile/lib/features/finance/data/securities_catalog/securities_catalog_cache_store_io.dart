import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'securities_catalog_cache_store_base.dart';

SecuritiesCatalogCacheStore createSecuritiesCatalogCacheStore() =>
    IoSecuritiesCatalogCacheStore();

/// Stores the downloaded catalog under the app-support directory, next to
/// (but independent of) the database. Writes go through a temp file + rename
/// so a crash never leaves a truncated catalog behind.
final class IoSecuritiesCatalogCacheStore
    implements SecuritiesCatalogCacheStore {
  IoSecuritiesCatalogCacheStore({Future<Directory> Function()? rootDirectory})
    : _rootDirectory = rootDirectory ?? getApplicationSupportDirectory;

  static const _catalogFile = 'securities.ndjson';
  static const _checkedFile = 'last_checked';

  final Future<Directory> Function() _rootDirectory;

  Future<Directory> _dir() async {
    final root = await _rootDirectory();
    return Directory(path.join(root.path, 'securities_catalog'));
  }

  Future<File> _file(String name) async =>
      File(path.join((await _dir()).path, name));

  @override
  Future<String?> read() async {
    final file = await _file(_catalogFile);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String raw) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    final target = File(path.join(dir.path, _catalogFile));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(raw, flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<void> delete() async {
    final file = await _file(_catalogFile);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<DateTime?> lastCheckedAt() async {
    final file = await _file(_checkedFile);
    if (!await file.exists()) return null;
    return DateTime.tryParse((await file.readAsString()).trim());
  }

  @override
  Future<void> markChecked(DateTime at) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    await File(path.join(dir.path, _checkedFile))
        .writeAsString(at.toUtc().toIso8601String(), flush: true);
  }
}
