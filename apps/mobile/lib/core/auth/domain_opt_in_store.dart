import 'package:drift/drift.dart' show Variable;

import '../../core/persistence/app_database.dart';
import 'domain_scope.dart';

/// Local persistence for [DomainOptIns]. Stored in `sync_meta` rather than
/// a new Drift table — the set is tiny (one row, comma-separated) and
/// `sync_meta` is already cross-domain key/value scratch space.
class DomainOptInStore {
  DomainOptInStore(this._db);

  static const String _key = 'lifeos.domain.optins';

  final AppDatabase _db;

  Future<DomainOptIns> read() async {
    final row = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [Variable.withString(_key)],
        )
        .getSingleOrNull();
    if (row == null) return DomainOptIns.financeOnly;
    final csv = row.read<String>('value');
    final wire = csv
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (wire.isEmpty) return DomainOptIns.financeOnly;
    return DomainOptIns.fromWire(wire);
  }

  Future<void> write(DomainOptIns optIns) async {
    final value = optIns.toWire().join(',');
    await _db.customStatement(
      'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [_key, value],
    );
  }
}
