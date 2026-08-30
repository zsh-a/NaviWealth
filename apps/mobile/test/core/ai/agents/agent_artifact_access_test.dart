import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_access.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';

import '../../../core/persistence/test_database.dart';

const _owner = 'artifact-user';

Future<T> _withRef<T>(
  ProviderContainer container,
  Future<T> Function(Ref ref) body,
) {
  final probe = FutureProvider<T>((ref) => body(ref));
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

ProviderContainer _container(AppDatabase db, {List<Agent> agents = const []}) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => db),
      currentUserIdProvider.overrideWithValue(() async => _owner),
      agentRegistryProvider.overrideWithValue(agents),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'readActiveAgentArtifact returns active current-user artifacts',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await DomainOptInStore(db)
          .write(DomainOptIns(const <DomainScope>{DomainScope.health}));
      final store = SqliteAgentArtifactStore(db: db);
      await store.save(_artifact(ownerUserId: _owner));
      final container = _container(db, agents: const <Agent>[_HealthAgent()]);

      final artifact = await _withRef(
        container,
        (ref) => readActiveAgentArtifact(
          ref,
          artifactId: 'health-artifact',
          expectedDomain: DomainScope.health.wire,
        ),
      );

      expect(artifact?.id, 'health-artifact');
    },
  );

  test(
    'readActiveAgentArtifact rejects artifacts from another owner',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await DomainOptInStore(db)
          .write(DomainOptIns(const <DomainScope>{DomainScope.health}));
      final store = SqliteAgentArtifactStore(db: db);
      await store.save(_artifact(ownerUserId: 'other-user'));
      final container = _container(db, agents: const <Agent>[_HealthAgent()]);

      final artifact = await _withRef(
        container,
        (ref) => readActiveAgentArtifact(ref, artifactId: 'health-artifact'),
      );

      expect(artifact, isNull);
    },
  );

  test('readActiveAgentArtifact rejects inactive domain artifacts', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    await store.save(_artifact(ownerUserId: _owner));
    final container = _container(db, agents: const <Agent>[_HealthAgent()]);

    final artifact = await _withRef(
      container,
      (ref) => readActiveAgentArtifact(ref, artifactId: 'health-artifact'),
    );

    expect(artifact, isNull);
  });

  test(
    'readActiveAgentArtifact rejects unregistered agent artifacts',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await DomainOptInStore(db)
          .write(DomainOptIns(const <DomainScope>{DomainScope.health}));
      final store = SqliteAgentArtifactStore(db: db);
      await store.save(_artifact(ownerUserId: _owner));
      final container = _container(db);

      final artifact = await _withRef(
        container,
        (ref) => readActiveAgentArtifact(ref, artifactId: 'health-artifact'),
      );

      expect(artifact, isNull);
    },
  );

  test('readActiveAgentArtifact rejects expected domain mismatches', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    await DomainOptInStore(db)
        .write(DomainOptIns(const <DomainScope>{DomainScope.health}));
    final store = SqliteAgentArtifactStore(db: db);
    await store.save(_artifact(ownerUserId: _owner));
    final container = _container(db, agents: const <Agent>[_HealthAgent()]);

    final artifact = await _withRef(
      container,
      (ref) => readActiveAgentArtifact(
        ref,
        artifactId: 'health-artifact',
        expectedDomain: DomainScope.knowledge.wire,
      ),
    );

    expect(artifact, isNull);
  });

  test('readActiveAgentArtifact rejects hidden artifacts', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    await DomainOptInStore(db)
        .write(DomainOptIns(const <DomainScope>{DomainScope.health}));
    final store = SqliteAgentArtifactStore(db: db);
    final now = DateTime.utc(2026, 7, 5, 12);
    await store.save(_artifact(id: 'dismissed', ownerUserId: _owner));
    await store.save(_artifact(id: 'snoozed', ownerUserId: _owner));
    await store.save(
      _artifact(
        id: 'expired',
        ownerUserId: _owner,
        expiresAt: now.subtract(const Duration(minutes: 1)),
      ),
    );
    await store.dismiss(ownerUserId: _owner, id: 'dismissed', dismissedAt: now);
    await store.snooze(
      ownerUserId: _owner,
      id: 'snoozed',
      until: now.add(const Duration(hours: 2)),
    );
    final container = _container(db, agents: const <Agent>[_HealthAgent()]);

    for (final id in const <String>['dismissed', 'snoozed', 'expired']) {
      final artifact = await _withRef(
        container,
        (ref) => readActiveAgentArtifact(ref, artifactId: id, visibleAt: now),
      );
      expect(artifact, isNull, reason: id);
    }
  });
}

AgentArtifact _artifact({
  String id = 'health-artifact',
  required String ownerUserId,
  DateTime? expiresAt,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: ownerUserId,
    agentId: 'health_agent',
    domain: DomainScope.health.wire,
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.info,
    title: 'Health Artifact',
    summary: 'Health summary',
    createdAt: DateTime.utc(2026, 7, 5),
    expiresAt: expiresAt,
  );
}

class _HealthAgent implements Agent {
  const _HealthAgent();

  @override
  String get id => 'health_agent';

  @override
  String get name => 'Health Agent';

  @override
  AgentSchedule get schedule => AgentSchedule.everyHours(24);

  @override
  Future<AgentRunResult> run(AgentContext ctx) {
    throw UnimplementedError();
  }
}
