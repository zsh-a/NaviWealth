import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

/// A reversible lifecycle mutation.
///
/// Undo is deliberately conditional: it only restores the fields changed by
/// this mutation when they still contain the value written by the mutation.
/// A later edit therefore wins instead of being overwritten by an old tile
/// snapshot.
class KnowledgeLifecycleChange {
  const KnowledgeLifecycleChange(this.undo);

  final Future<bool> Function() undo;
}

final knowledgeLifecycleServiceProvider =
    FutureProvider<KnowledgeLifecycleService>((ref) async {
      return KnowledgeLifecycleService(
        repository: await ref.watch(knowledgeRepositoryProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

/// Owns the small, one-tap state transitions shared by Library and Review.
///
/// Every mutation re-reads the current row immediately before writing. UI
/// objects are presentation snapshots and are never used as write bases.
class KnowledgeLifecycleService {
  KnowledgeLifecycleService({
    required KnowledgeRepository repository,
    required MutationStamper stamper,
  }) : _repository = repository,
       _stamper = stamper;

  final KnowledgeRepository _repository;
  final MutationStamper _stamper;

  Future<KnowledgeLifecycleChange?> togglePrinciple({
    required String ownerUserId,
    required String id,
  }) async {
    final current = await _repository.findPrinciple(
      ownerUserId: ownerUserId,
      id: id,
    );
    if (current == null || current.sync.deletedAt != null) return null;
    final nextStatus = switch (current.status) {
      PrincipleStatus.active => PrincipleStatus.paused,
      PrincipleStatus.paused => PrincipleStatus.active,
      // Retirement is an explicit lifecycle decision and is not reversible
      // through a one-tap contextual action.
      PrincipleStatus.retired => null,
    };
    if (nextStatus == null) return null;

    await _repository.upsertPrinciple(
      _principleWith(current, status: nextStatus, sync: await _freshSync()),
    );
    return KnowledgeLifecycleChange(() async {
      final latest = await _repository.findPrinciple(
        ownerUserId: ownerUserId,
        id: id,
      );
      if (latest == null || latest.status != nextStatus) return false;
      await _repository.upsertPrinciple(
        _principleWith(
          latest,
          status: current.status,
          sync: await _freshSync(),
        ),
      );
      return true;
    });
  }

  Future<KnowledgeLifecycleChange?> verifyAssumption({
    required String ownerUserId,
    required String id,
  }) async {
    final current = await _repository.findAssumption(
      ownerUserId: ownerUserId,
      id: id,
    );
    if (current == null ||
        current.sync.deletedAt != null ||
        (current.status != AssumptionStatus.active &&
            current.status != AssumptionStatus.weakened)) {
      return null;
    }

    final previousVerifiedAt = current.lastVerifiedAt;
    final sync = await _freshSync();
    final appliedAt = sync.updatedAt;
    await _repository.upsertAssumption(
      _assumptionWith(current, lastVerifiedAt: appliedAt, sync: sync),
    );
    return KnowledgeLifecycleChange(() async {
      final latest = await _repository.findAssumption(
        ownerUserId: ownerUserId,
        id: id,
      );
      if (latest == null ||
          !_sameNullableInstant(latest.lastVerifiedAt, appliedAt)) {
        return false;
      }
      await _repository.upsertAssumption(
        _assumptionWith(
          latest,
          lastVerifiedAt: previousVerifiedAt,
          sync: await _freshSync(),
        ),
      );
      return true;
    });
  }

  Future<KnowledgeLifecycleChange?> completeOrResumeRoutine({
    required String ownerUserId,
    required String id,
  }) async {
    final current = await _repository.findRoutine(
      ownerUserId: ownerUserId,
      id: id,
    );
    if (current == null ||
        current.sync.deletedAt != null ||
        current.status == RoutineStatus.archived) {
      return null;
    }

    final sync = await _freshSync();
    final now = sync.updatedAt;
    const nextStatus = RoutineStatus.active;
    final DateTime nextDueAt;
    final DateTime? lastDoneAt;
    if (current.status == RoutineStatus.active) {
      nextDueAt = now.add(Duration(days: current.intervalDays));
      lastDoneAt = now;
    } else {
      // A paused routine resumes into the future instead of immediately
      // surfacing as overdue. A deliberately future due date is preserved.
      nextDueAt = current.nextDueAt.isAfter(now)
          ? current.nextDueAt
          : now.add(Duration(days: current.intervalDays));
      lastDoneAt = current.lastDoneAt;
    }

    await _repository.upsertRoutine(
      _routineWith(
        current,
        status: nextStatus,
        nextDueAt: nextDueAt,
        lastDoneAt: lastDoneAt,
        sync: sync,
      ),
    );
    return KnowledgeLifecycleChange(() async {
      final latest = await _repository.findRoutine(
        ownerUserId: ownerUserId,
        id: id,
      );
      if (latest == null ||
          latest.status != nextStatus ||
          !_sameInstant(latest.nextDueAt, nextDueAt) ||
          !_sameNullableInstant(latest.lastDoneAt, lastDoneAt)) {
        return false;
      }
      await _repository.upsertRoutine(
        _routineWith(
          latest,
          status: current.status,
          nextDueAt: current.nextDueAt,
          lastDoneAt: current.lastDoneAt,
          sync: await _freshSync(),
        ),
      );
      return true;
    });
  }

  Future<KnowledgeLifecycleChange?> startExperiment({
    required String ownerUserId,
    required String id,
  }) async {
    final current = await _repository.findExperiment(
      ownerUserId: ownerUserId,
      id: id,
    );
    // An abandoned experiment is historical evidence. Restarting it must
    // create a fresh experiment, not erase the old result and conclusion.
    if (current == null ||
        current.sync.deletedAt != null ||
        current.status != ExperimentStatus.planned) {
      return null;
    }

    final sync = await _freshSync();
    final appliedStartedAt = sync.updatedAt;
    await _repository.upsertExperiment(
      _experimentWith(
        current,
        status: ExperimentStatus.running,
        startedAt: appliedStartedAt,
        endedAt: null,
        sync: sync,
      ),
    );
    return KnowledgeLifecycleChange(() async {
      final latest = await _repository.findExperiment(
        ownerUserId: ownerUserId,
        id: id,
      );
      if (latest == null ||
          latest.status != ExperimentStatus.running ||
          !_sameInstant(latest.startedAt, appliedStartedAt) ||
          latest.endedAt != null) {
        return false;
      }
      await _repository.upsertExperiment(
        _experimentWith(
          latest,
          status: current.status,
          startedAt: current.startedAt,
          endedAt: current.endedAt,
          sync: await _freshSync(),
        ),
      );
      return true;
    });
  }

  Future<SyncMeta> _freshSync() async {
    final stamp = await _stamper.stamp();
    return SyncMeta(
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
  }
}

bool _sameInstant(DateTime left, DateTime right) =>
    left.microsecondsSinceEpoch == right.microsecondsSinceEpoch;

bool _sameNullableInstant(DateTime? left, DateTime? right) =>
    left == null || right == null ? left == right : _sameInstant(left, right);

KnowledgePrinciple _principleWith(
  KnowledgePrinciple value, {
  required PrincipleStatus status,
  required SyncMeta sync,
}) => KnowledgePrinciple(
  id: value.id,
  statement: value.statement,
  rationaleMd: value.rationaleMd,
  scope: value.scope,
  status: status,
  declaredAt: value.declaredAt,
  mergedIntoId: value.mergedIntoId,
  sync: sync,
);

KnowledgeAssumption _assumptionWith(
  KnowledgeAssumption value, {
  required DateTime? lastVerifiedAt,
  required SyncMeta sync,
}) => KnowledgeAssumption(
  id: value.id,
  statement: value.statement,
  confidence: value.confidence,
  scope: value.scope,
  evidenceIds: value.evidenceIds,
  status: value.status,
  declaredAt: value.declaredAt,
  lastVerifiedAt: lastVerifiedAt,
  mergedIntoId: value.mergedIntoId,
  sync: sync,
);

KnowledgeRoutine _routineWith(
  KnowledgeRoutine value, {
  required RoutineStatus status,
  required DateTime nextDueAt,
  required DateTime? lastDoneAt,
  required SyncMeta sync,
}) => KnowledgeRoutine(
  id: value.id,
  statement: value.statement,
  intervalDays: value.intervalDays,
  nextDueAt: nextDueAt,
  lastDoneAt: lastDoneAt,
  scope: value.scope,
  status: status,
  createdAt: value.createdAt,
  sync: sync,
);

KnowledgeExperiment _experimentWith(
  KnowledgeExperiment value, {
  required ExperimentStatus status,
  required DateTime startedAt,
  required DateTime? endedAt,
  required SyncMeta sync,
}) => KnowledgeExperiment(
  id: value.id,
  hypothesis: value.hypothesis,
  methodMd: value.methodMd,
  metrics: value.metrics,
  status: status,
  resultMd: value.resultMd,
  conclusionMd: value.conclusionMd,
  targetAssumptionId: value.targetAssumptionId,
  startedAt: startedAt,
  endedAt: endedAt,
  mergedIntoId: value.mergedIntoId,
  sync: sync,
);
