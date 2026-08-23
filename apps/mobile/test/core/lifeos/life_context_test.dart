import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/life_context_composition.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/source_identity.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/life_context.dart';
import 'package:naviwealth/core/lifeos/life_signal.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_snapshot.dart';

const _owner = 'profile-user';
final _now = DateTime.utc(2026, 8, 23, 8);

EventRecord _event({
  required String id,
  required DomainScope domain,
  required DateTime occurredAt,
  required DateTime observedAt,
}) => EventRecord(
  id: id,
  domain: domain,
  kind: EventKind.domain(domain, 'state_changed'),
  occurredAt: occurredAt,
  observedAt: observedAt,
  sourceIdentity: SourceIdentity(
    domain: domain,
    rowFamily: '${domain.wire}:fixture',
    rowId: id,
    fingerprint: 'fixture-$id',
  ),
  ownerUserId: _owner,
  summary: '$domain changed',
  facts: const <String, Object?>{},
  entities: const <String>{},
);

void main() {
  test('marks freshness and excludes inactive-domain changes', () {
    final profile = PersonalProfileSnapshot(asOf: _now, facts: const []);
    final finance = _event(
      id: 'finance-old',
      domain: DomainScope.finance,
      occurredAt: _now.subtract(const Duration(days: 4)),
      observedAt: _now.subtract(const Duration(days: 4)),
    );
    final health = _event(
      id: 'health-fresh',
      domain: DomainScope.health,
      occurredAt: _now.subtract(const Duration(hours: 2)),
      observedAt: _now.subtract(const Duration(hours: 1)),
    );
    final knowledge = _event(
      id: 'knowledge-inactive',
      domain: DomainScope.knowledge,
      occurredAt: _now,
      observedAt: _now,
    );
    const active = <DomainScope>{DomainScope.finance, DomainScope.health};
    final signals = LifeSignalSnapshot(
      observedAt: _now,
      events: const <LifeEvent>[],
      evaluatedSourceFamilies: const <String>{
        'fin:journal_entries',
        'health:health_metrics',
      },
      evaluatedSourceFamiliesByDomain: const <DomainScope, Set<String>>{
        DomainScope.finance: <String>{'fin:journal_entries'},
        DomainScope.health: <String>{'health:health_metrics'},
      },
    );

    LifeContextSnapshot build(DateTime generatedAt, List<EventRecord> events) {
      return composeLifeContextSnapshot(
        ownerUserId: _owner,
        generatedAt: generatedAt,
        profile: profile,
        activeDomains: active,
        lifeSignals: signals,
        recentChanges: events,
        relevantHistory: const [],
      );
    }

    final first = build(_now, <EventRecord>[finance, health, knowledge]);
    final second = build(_now.add(const Duration(minutes: 10)), <EventRecord>[
      knowledge,
      health,
      finance,
    ]);

    expect(
      first.domainStates
          .singleWhere((state) => state.domain == DomainScope.finance)
          .freshness,
      LifeContextFreshness.stale,
    );
    expect(
      first.domainStates
          .singleWhere((state) => state.domain == DomainScope.health)
          .freshness,
      LifeContextFreshness.fresh,
    );
    expect(
      first.recentChanges.map((event) => event.id),
      isNot(contains('knowledge-inactive')),
    );
    expect(second.fingerprint, first.fingerprint);
  });
}
