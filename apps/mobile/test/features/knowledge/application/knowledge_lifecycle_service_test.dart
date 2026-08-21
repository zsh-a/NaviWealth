import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/application/knowledge_lifecycle_service.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

final _created = DateTime.utc(2026, 1, 1);

SyncMeta _meta({int millis = 1}) => SyncMeta(
  ownerUserId: 'user',
  updatedAt: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
  updatedByDevice: 'device',
  hlc: Hlc(wallMillis: millis, counter: 0, nodeId: 'device'),
);

void main() {
  late AppDatabase db;
  late KnowledgeRepository repository;
  late KnowledgeLifecycleService service;

  setUp(() {
    db = makeTestDatabase();
    repository = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
    service = KnowledgeLifecycleService(
      repository: repository,
      stamper: makeStubStamper(
        userId: 'user',
        deviceId: 'device',
        initialMillis: DateTime.utc(2026, 8, 21).millisecondsSinceEpoch,
      ),
    );
  });

  tearDown(() => db.close());

  test('experiment start and undo preserve a newer unrelated edit', () async {
    final experiment = KnowledgeExperiment(
      id: 'experiment',
      hypothesis: 'Smaller batches are faster',
      methodMd: 'Measure lead time',
      metrics: const <String>['lead time'],
      status: ExperimentStatus.planned,
      startedAt: _created,
      sync: _meta(),
    );
    await repository.upsertExperiment(experiment);

    final change = await service.startExperiment(
      ownerUserId: 'user',
      id: experiment.id,
    );
    final running = await repository.findExperiment(
      ownerUserId: 'user',
      id: experiment.id,
    );
    expect(running?.status, ExperimentStatus.running);
    expect(running?.startedAt, isNot(_created));

    await repository.upsertExperiment(
      KnowledgeExperiment(
        id: running!.id,
        hypothesis: running.hypothesis,
        methodMd: running.methodMd,
        metrics: running.metrics,
        status: running.status,
        resultMd: 'A newer observation',
        conclusionMd: running.conclusionMd,
        targetAssumptionId: running.targetAssumptionId,
        startedAt: running.startedAt,
        endedAt: running.endedAt,
        mergedIntoId: running.mergedIntoId,
        sync: _meta(millis: 9_999_999_999_999),
      ),
    );

    expect(await change?.undo(), isTrue);
    final restored = await repository.findExperiment(
      ownerUserId: 'user',
      id: experiment.id,
    );
    expect(restored?.status, ExperimentStatus.planned);
    expect(restored?.startedAt.toUtc(), _created);
    expect(restored?.resultMd, 'A newer observation');
  });

  test('paused overdue routine resumes with a future due date', () async {
    final routine = KnowledgeRoutine(
      id: 'routine',
      statement: 'Review quarterly',
      intervalDays: 90,
      nextDueAt: _created,
      scope: '*',
      status: RoutineStatus.paused,
      createdAt: _created,
      sync: _meta(),
    );
    await repository.upsertRoutine(routine);

    final change = await service.completeOrResumeRoutine(
      ownerUserId: 'user',
      id: routine.id,
    );
    final resumed = await repository.findRoutine(
      ownerUserId: 'user',
      id: routine.id,
    );
    expect(change, isNotNull);
    expect(resumed?.status, RoutineStatus.active);
    expect(resumed!.nextDueAt.isAfter(DateTime.utc(2026, 8, 21)), isTrue);
    expect(resumed.lastDoneAt, isNull);
  });

  test('terminal lifecycle states require explicit editing', () async {
    await repository.upsertPrinciple(
      KnowledgePrinciple(
        id: 'retired',
        statement: 'Historical principle',
        rationaleMd: '',
        scope: '*',
        status: PrincipleStatus.retired,
        declaredAt: _created,
        sync: _meta(),
      ),
    );
    await repository.upsertExperiment(
      KnowledgeExperiment(
        id: 'abandoned',
        hypothesis: 'Historical experiment',
        methodMd: '',
        metrics: const <String>[],
        status: ExperimentStatus.abandoned,
        resultMd: 'No signal',
        startedAt: _created,
        endedAt: _created.add(const Duration(days: 2)),
        sync: _meta(),
      ),
    );

    expect(
      await service.togglePrinciple(ownerUserId: 'user', id: 'retired'),
      isNull,
    );
    expect(
      await service.startExperiment(ownerUserId: 'user', id: 'abandoned'),
      isNull,
    );
  });
}
