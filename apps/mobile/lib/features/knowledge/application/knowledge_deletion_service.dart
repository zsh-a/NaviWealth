import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';

final knowledgeDeletionServiceProvider =
    FutureProvider<KnowledgeDeletionService>((ref) async {
      return KnowledgeDeletionService(
        repository: await ref.watch(knowledgeRepositoryProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

class KnowledgeDeletionService {
  KnowledgeDeletionService({
    required KnowledgeRepository repository,
    required MutationStamper stamper,
  }) : _repository = repository,
       _stamper = stamper;

  final KnowledgeRepository _repository;
  final MutationStamper _stamper;

  Future<bool> delete({
    required KnowledgeEntryKind kind,
    required String id,
  }) async {
    final stamp = await _stamper.stamp();
    await _repository.deleteEntry(
      kind: kind,
      id: id,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
        deletedAt: stamp.now,
      ),
    );
    return true;
  }
}
