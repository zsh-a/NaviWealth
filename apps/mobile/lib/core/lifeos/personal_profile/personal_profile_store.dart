library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../ai/contracts/context_evidence.dart';
import '../../persistence/app_database.dart';
import 'personal_profile_fact.dart';

abstract interface class PersonalProfileStore {
  Future<void> create(PersonalProfileFact fact);

  Future<void> restore(PersonalProfileFact fact);

  Future<PersonalProfileFact?> read({
    required String ownerUserId,
    required String id,
  });

  Future<List<PersonalProfileFact>> listActive({
    required String ownerUserId,
    required DateTime at,
    required Set<String> activeDomainScopes,
    int limit = 64,
  });

  /// Returns current facts for user-managed Settings UI, including facts
  /// whose optional domain is currently disabled.
  Future<List<PersonalProfileFact>> listCurrent({
    required String ownerUserId,
    required DateTime at,
    int limit = 256,
  });

  Future<void> supersede({
    required String ownerUserId,
    required String priorId,
    required PersonalProfileFact replacement,
    required DateTime at,
  });

  Future<void> forget({required String ownerUserId, required String id});
}

final class SqlitePersonalProfileStore implements PersonalProfileStore {
  const SqlitePersonalProfileStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> create(PersonalProfileFact fact) async {
    _validate(fact);
    await _db.transaction(() async {
      await _ensureNoOverlap(fact);
      await _insert(fact);
    });
  }

  @override
  Future<void> restore(PersonalProfileFact fact) async {
    _validate(fact);
    await _db.transaction(() async {
      await _db.customStatement(
        'DELETE FROM personal_profile_facts WHERE id = ?',
        <Object?>[fact.id],
      );
      await _ensureNoOverlap(fact);
      await _insert(fact);
    });
  }

  @override
  Future<PersonalProfileFact?> read({
    required String ownerUserId,
    required String id,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM personal_profile_facts '
          'WHERE owner_user_id = ? AND id = ?',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withString(id),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<PersonalProfileFact>> listActive({
    required String ownerUserId,
    required DateTime at,
    required Set<String> activeDomainScopes,
    int limit = 64,
  }) async {
    if (limit <= 0) return const <PersonalProfileFact>[];
    final instant = at.toUtc().millisecondsSinceEpoch;
    final variables = <Variable<Object>>[
      Variable.withString(ownerUserId),
      Variable.withInt(instant),
      Variable.withInt(instant),
    ];
    var domainFilter = 'domain_scope IS NULL';
    if (activeDomainScopes.isNotEmpty) {
      final placeholders = List<String>.filled(
        activeDomainScopes.length,
        '?',
      ).join(', ');
      domainFilter =
          '(domain_scope IS NULL OR domain_scope IN ($placeholders))';
      variables.addAll(activeDomainScopes.map(Variable.withString));
    }
    final rows = await _db
        .customSelect(
          'SELECT * FROM personal_profile_facts '
          'WHERE owner_user_id = ? AND valid_from <= ? '
          'AND (valid_until IS NULL OR valid_until > ?) '
          'AND $domainFilter '
          'ORDER BY CASE kind '
          "WHEN 'constraint' THEN 0 WHEN 'rule' THEN 1 "
          "WHEN 'goal' THEN 2 ELSE 3 END, fact_key, updated_at DESC "
          'LIMIT ${limit.clamp(1, 256)}',
          variables: variables,
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<PersonalProfileFact>> listCurrent({
    required String ownerUserId,
    required DateTime at,
    int limit = 256,
  }) async {
    if (limit <= 0) return const <PersonalProfileFact>[];
    final instant = at.toUtc().millisecondsSinceEpoch;
    final rows = await _db
        .customSelect(
          'SELECT * FROM personal_profile_facts '
          'WHERE owner_user_id = ? AND valid_from <= ? '
          'AND (valid_until IS NULL OR valid_until > ?) '
          'ORDER BY CASE kind '
          "WHEN 'constraint' THEN 0 WHEN 'rule' THEN 1 "
          "WHEN 'goal' THEN 2 ELSE 3 END, fact_key, updated_at DESC "
          'LIMIT ${limit.clamp(1, 512)}',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withInt(instant),
            Variable.withInt(instant),
          ],
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> supersede({
    required String ownerUserId,
    required String priorId,
    required PersonalProfileFact replacement,
    required DateTime at,
  }) async {
    _validate(replacement);
    if (replacement.ownerUserId != ownerUserId ||
        replacement.supersedesFactId != priorId) {
      throw StateError('profile replacement ownership or lineage mismatch');
    }
    final instant = at.toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final changed = await _db.customUpdate(
        'UPDATE personal_profile_facts '
        'SET valid_until = ?, updated_at = ? '
        'WHERE owner_user_id = ? AND id = ? AND valid_until IS NULL',
        variables: <Variable<Object>>[
          Variable.withInt(instant),
          Variable.withInt(instant),
          Variable.withString(ownerUserId),
          Variable.withString(priorId),
        ],
      );
      if (changed != 1) {
        throw StateError('active profile fact was not found');
      }
      await _ensureNoOverlap(replacement);
      await _insert(replacement);
    });
  }

  @override
  Future<void> forget({required String ownerUserId, required String id}) {
    return _db.customStatement(
      'DELETE FROM personal_profile_facts '
      'WHERE owner_user_id = ? AND id = ?',
      <Object?>[ownerUserId, id],
    );
  }

  Future<void> _insert(PersonalProfileFact fact) {
    return _db.customStatement(
      'INSERT INTO personal_profile_facts ('
      'id, owner_user_id, kind, fact_key, value_json, summary, domain_scope, '
      'authority, provenance_json, confidence, confirmed_at, valid_from, '
      'valid_until, supersedes_fact_id, created_at, updated_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        fact.id,
        fact.ownerUserId,
        fact.kind.wire,
        fact.key,
        jsonEncode(fact.value),
        fact.summary,
        fact.domainScope,
        fact.authority.wire,
        jsonEncode(fact.provenance.toJson()),
        fact.confidence,
        fact.confirmedAt?.toUtc().millisecondsSinceEpoch,
        fact.validFrom.toUtc().millisecondsSinceEpoch,
        fact.validUntil?.toUtc().millisecondsSinceEpoch,
        fact.supersedesFactId,
        fact.createdAt.toUtc().millisecondsSinceEpoch,
        fact.updatedAt.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> _ensureNoOverlap(PersonalProfileFact fact) async {
    final variables = <Variable<Object>>[
      Variable.withString(fact.ownerUserId),
      Variable.withString(fact.kind.wire),
      Variable.withString(fact.key),
    ];
    final domainClause = fact.domainScope == null
        ? 'domain_scope IS NULL'
        : 'domain_scope = ?';
    if (fact.domainScope case final String domainScope) {
      variables.add(Variable.withString(domainScope));
    }
    variables.add(
      Variable.withInt(fact.validFrom.toUtc().millisecondsSinceEpoch),
    );
    final newEnd = fact.validUntil?.toUtc().millisecondsSinceEpoch;
    final startsBeforeNewEnd = newEnd == null ? '1 = 1' : 'valid_from < ?';
    if (newEnd != null) variables.add(Variable.withInt(newEnd));
    final overlap = await _db
        .customSelect(
          'SELECT id FROM personal_profile_facts '
          'WHERE owner_user_id = ? AND kind = ? AND fact_key = ? '
          'AND $domainClause '
          'AND (valid_until IS NULL OR valid_until > ?) '
          'AND $startsBeforeNewEnd LIMIT 1',
          variables: variables,
        )
        .getSingleOrNull();
    if (overlap != null) {
      throw StateError(
        'profile fact validity overlaps an existing fact with the same key',
      );
    }
  }

  void _validate(PersonalProfileFact fact) {
    if (fact.id.trim().isEmpty ||
        fact.ownerUserId.trim().isEmpty ||
        fact.key.trim().isEmpty ||
        fact.summary.trim().isEmpty) {
      throw ArgumentError(
        'profile fact identity, key, and summary are required',
      );
    }
    if (fact.confidence < 0 || fact.confidence > 1) {
      throw ArgumentError.value(fact.confidence, 'confidence');
    }
    if (fact.authority != EvidenceAuthority.userConfirmed ||
        fact.confirmedAt == null) {
      throw ArgumentError(
        'profile facts must be explicitly user-confirmed before storage',
      );
    }
    if (fact.validUntil != null &&
        !fact.validUntil!.toUtc().isAfter(fact.validFrom.toUtc())) {
      throw ArgumentError('validUntil must follow validFrom');
    }
  }

  PersonalProfileFact _fromRow(QueryRow row) {
    final kind = PersonalProfileFactKindWire.tryParse(row.read<String>('kind'));
    if (kind == null) throw StateError('invalid personal profile fact kind');
    final provenanceRaw = jsonDecode(row.read<String>('provenance_json'));
    return PersonalProfileFact(
      id: row.read<String>('id'),
      ownerUserId: row.read<String>('owner_user_id'),
      kind: kind,
      key: row.read<String>('fact_key'),
      value: jsonDecode(row.read<String>('value_json')),
      summary: row.read<String>('summary'),
      domainScope: row.readNullable<String>('domain_scope'),
      authority: EvidenceAuthorityWire.parse(row.read<String>('authority')),
      provenance: EvidenceProvenance.fromJson(
        provenanceRaw is Map
            ? provenanceRaw.map((key, value) => MapEntry('$key', value))
            : const <String, Object?>{},
      ),
      confidence: row.read<double>('confidence'),
      confirmedAt: _date(row.readNullable<int>('confirmed_at')),
      validFrom: _date(row.read<int>('valid_from'))!,
      validUntil: _date(row.readNullable<int>('valid_until')),
      supersedesFactId: row.readNullable<String>('supersedes_fact_id'),
      createdAt: _date(row.read<int>('created_at'))!,
      updatedAt: _date(row.read<int>('updated_at'))!,
    );
  }
}

DateTime? _date(int? millis) => millis == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
