import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_edit_service.dart';

final knowledgeRelationServiceProvider =
    FutureProvider<KnowledgeRelationService>((ref) async {
      return KnowledgeRelationService(
        repository: await ref.watch(knowledgeRepositoryProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

class KnowledgeRelationService {
  const KnowledgeRelationService({
    required KnowledgeRepository repository,
    required MutationStamper stamper,
  }) : _repository = repository,
       _stamper = stamper;

  final KnowledgeRepository _repository;
  final MutationStamper _stamper;

  Future<void> add({
    required String fromKind,
    required String fromId,
    required String toKind,
    required String toId,
  }) async {
    if (fromKind == toKind && fromId == toId) {
      throw ArgumentError('Cannot link an item to itself');
    }
    final stamp = await _stamper.stamp();
    await _repository.transaction(() async {
      await _requireLive(stamp.ownerUserId, fromKind, fromId);
      await _requireLive(stamp.ownerUserId, toKind, toId);
      final id = knowledgeRelationId(
        fromKind: fromKind,
        fromId: fromId,
        relation: KnowledgeRelationType.relatedTo,
        toKind: toKind,
        toId: toId,
      );
      final prior = await _repository.findRelation(
        ownerUserId: stamp.ownerUserId,
        id: id,
      );
      if (prior != null && prior.sync.deletedAt == null) return;
      await _repository.upsertRelation(
        KnowledgeRelation(
          id: id,
          fromKind: fromKind,
          fromId: fromId,
          relation: KnowledgeRelationType.relatedTo,
          toKind: toKind,
          toId: toId,
          createdAt: prior?.createdAt ?? stamp.now,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    });
  }

  Future<KnowledgeRelation> remove(KnowledgeRelation relation) async {
    final stamp = await _stamper.stamp();
    return _repository.transaction(() async {
      final current = await _repository.findRelation(
        ownerUserId: stamp.ownerUserId,
        id: relation.id,
      );
      if (current == null || current.sync.deletedAt != null) {
        throw KnowledgeEditFailure.missing;
      }
      if (current.sync.hlc != relation.sync.hlc) {
        throw KnowledgeEditFailure.changed;
      }
      final deleted = _withSync(
        current,
        SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
          deletedAt: stamp.now,
        ),
      );
      await _repository.upsertRelation(deleted);
      return deleted;
    });
  }

  Future<void> restore(KnowledgeRelation receipt) async {
    final stamp = await _stamper.stamp();
    await _repository.transaction(() async {
      final current = await _repository.findRelation(
        ownerUserId: stamp.ownerUserId,
        id: receipt.id,
      );
      if (current == null ||
          current.sync.hlc != receipt.sync.hlc ||
          current.sync.deletedAt == null) {
        throw KnowledgeEditFailure.changed;
      }
      await _requireLive(stamp.ownerUserId, current.fromKind, current.fromId);
      await _requireLive(stamp.ownerUserId, current.toKind, current.toId);
      await _repository.upsertRelation(
        _withSync(
          current,
          SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    });
  }

  Future<void> _requireLive(String owner, String kind, String id) async {
    final sync = switch (kind) {
      'note' => (await _repository.findNote(ownerUserId: owner, id: id))?.sync,
      'decision' => (await _repository.findDecision(
        ownerUserId: owner,
        id: id,
      ))?.sync,
      _ => null,
    };
    if (sync == null || sync.deletedAt != null) {
      throw KnowledgeEditFailure.missing;
    }
  }

  KnowledgeRelation _withSync(KnowledgeRelation relation, SyncMeta sync) =>
      KnowledgeRelation(
        id: relation.id,
        fromKind: relation.fromKind,
        fromId: relation.fromId,
        relation: relation.relation,
        toKind: relation.toKind,
        toId: relation.toId,
        createdAt: relation.createdAt,
        sync: sync,
      );
}
