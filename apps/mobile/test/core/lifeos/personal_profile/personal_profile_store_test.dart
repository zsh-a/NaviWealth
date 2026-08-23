import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/context_evidence.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_fact.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_snapshot.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

import '../../persistence/test_database.dart';

const _owner = 'user-1';
final _now = DateTime.utc(2026, 8, 23, 12);

PersonalProfileFact _fact({
  required String id,
  String key = 'cash_buffer_months',
  Object? value = 12,
  String summary = 'Keep a 12 month cash buffer.',
  String? domainScope = 'finance',
  DateTime? validFrom,
  DateTime? validUntil,
  String? supersedes,
  String ownerUserId = _owner,
}) => PersonalProfileFact(
  id: id,
  ownerUserId: ownerUserId,
  kind: PersonalProfileFactKind.constraint,
  key: key,
  value: value,
  summary: summary,
  domainScope: domainScope,
  authority: EvidenceAuthority.userConfirmed,
  provenance: EvidenceProvenance(
    source: 'settings_profile',
    sourceId: id,
    observedAt: _now,
  ),
  confidence: 1,
  confirmedAt: _now,
  validFrom: validFrom ?? _now,
  validUntil: validUntil,
  supersedesFactId: supersedes,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  late AppDatabase db;
  late SqlitePersonalProfileStore store;

  setUp(() {
    db = makeTestDatabase();
    store = SqlitePersonalProfileStore(db);
  });

  tearDown(() => db.close());

  test('round-trips structured evidence and isolates owners', () async {
    await store.create(_fact(id: 'fact-1'));

    final restored = await store.read(ownerUserId: _owner, id: 'fact-1');
    expect(restored?.value, 12);
    expect(restored?.authority, EvidenceAuthority.userConfirmed);
    expect(restored?.provenance.source, 'settings_profile');
    expect(await store.read(ownerUserId: 'other', id: 'fact-1'), isNull);
  });

  test(
    'active snapshot includes global and enabled-domain facts only',
    () async {
      await store.create(_fact(id: 'finance'));
      await store.create(
        _fact(id: 'health', key: 'sleep_target', domainScope: 'health'),
      );
      await store.create(
        _fact(id: 'global', key: 'communication', domainScope: null),
      );

      final snapshot = await PersonalProfileSnapshotBuilder(store).build(
        ownerUserId: _owner,
        activeDomainScopes: const <String>{'finance'},
        at: _now,
      );
      expect(
        snapshot.facts.map((fact) => fact.id),
        containsAll(['finance', 'global']),
      );
      expect(snapshot.facts.map((fact) => fact.id), isNot(contains('health')));

      final managed = await store.listCurrent(ownerUserId: _owner, at: _now);
      expect(managed.map((fact) => fact.id), contains('health'));
    },
  );

  test(
    'transactional supersede closes prior and exposes replacement',
    () async {
      final prior = _fact(id: 'old');
      await store.create(prior);
      final replacement = _fact(
        id: 'new',
        value: 9,
        summary: 'Keep a 9 month cash buffer.',
        supersedes: prior.id,
        validFrom: _now.add(const Duration(minutes: 1)),
      );
      final changedAt = replacement.validFrom;

      await store.supersede(
        ownerUserId: _owner,
        priorId: prior.id,
        replacement: replacement,
        at: changedAt,
      );

      expect(
        (await store.read(ownerUserId: _owner, id: prior.id))?.validUntil,
        changedAt,
      );
      final current = await store.listCurrent(
        ownerUserId: _owner,
        at: changedAt.add(const Duration(seconds: 1)),
      );
      expect(current.map((fact) => fact.id), ['new']);
      expect(current.single.supersedesFactId, 'old');
    },
  );

  test('duplicate current key is rejected', () async {
    await store.create(_fact(id: 'one'));
    await expectLater(store.create(_fact(id: 'two')), throwsA(isA<Object>()));
  });

  test(
    'unconfirmed model inference cannot enter authoritative profile',
    () async {
      final inferred = PersonalProfileFact(
        id: 'inferred',
        ownerUserId: _owner,
        kind: PersonalProfileFactKind.preference,
        key: 'risk_tolerance',
        value: 'aggressive',
        summary: 'Likely prefers aggressive investments.',
        authority: EvidenceAuthority.modelDerived,
        provenance: const EvidenceProvenance(source: 'agent_inference'),
        confidence: 0.68,
        validFrom: _now,
        createdAt: _now,
        updatedAt: _now,
      );

      await expectLater(store.create(inferred), throwsArgumentError);
    },
  );

  test(
    'finite validity windows cannot overlap for the same profile key',
    () async {
      await store.create(
        _fact(
          id: 'first-window',
          validUntil: _now.add(const Duration(days: 10)),
        ),
      );

      await expectLater(
        store.create(
          _fact(
            id: 'overlap',
            validFrom: _now.add(const Duration(days: 5)),
            validUntil: _now.add(const Duration(days: 15)),
          ),
        ),
        throwsStateError,
      );

      await store.create(
        _fact(
          id: 'adjacent',
          validFrom: _now.add(const Duration(days: 10)),
          validUntil: _now.add(const Duration(days: 20)),
        ),
      );
      expect(await store.read(ownerUserId: _owner, id: 'adjacent'), isNotNull);
    },
  );

  test('forget physically deletes only the owned fact', () async {
    await store.create(_fact(id: 'mine'));
    await store.create(
      _fact(id: 'theirs', key: 'other_key', ownerUserId: 'other'),
    );

    await store.forget(ownerUserId: _owner, id: 'mine');
    expect(await store.read(ownerUserId: _owner, id: 'mine'), isNull);
    expect(await store.read(ownerUserId: 'other', id: 'theirs'), isNotNull);
  });
}
