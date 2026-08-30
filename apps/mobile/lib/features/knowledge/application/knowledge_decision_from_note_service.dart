/// Creates a Decision and its source Note relation as one user action.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

final knowledgeDecisionFromNoteServiceProvider =
    FutureProvider<KnowledgeDecisionFromNoteService>((ref) async {
      return KnowledgeDecisionFromNoteService(
        repository: await ref.watch(knowledgeRepositoryProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

class KnowledgeDecisionFromNoteService {
  KnowledgeDecisionFromNoteService({
    required KnowledgeRepository repository,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _repository = repository,
       _stamper = stamper,
       _uuid = uuid;

  final KnowledgeRepository _repository;
  final MutationStamper _stamper;
  final Uuid _uuid;

  Future<KnowledgeDecision> create({
    required String noteId,
    required String question,
    required String selectedLabel,
    String rationaleMd = '',
  }) async {
    final normalizedQuestion = question.trim();
    final normalizedSelection = selectedLabel.trim();
    if (normalizedQuestion.isEmpty) {
      throw ArgumentError.value(question, 'question', 'must not be empty');
    }
    if (normalizedSelection.isEmpty) {
      throw ArgumentError.value(
        selectedLabel,
        'selectedLabel',
        'must not be empty',
      );
    }
    final stamp = await _stamper.stamp();
    final sync = SyncMeta(
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    final decision = KnowledgeDecision(
      id: _uuid.v4(),
      question: normalizedQuestion,
      options: <DecisionOption>[DecisionOption(label: normalizedSelection)],
      selectedLabel: normalizedSelection,
      rationaleMd: rationaleMd.trim(),
      status: DecisionStatus.active,
      decidedAt: stamp.now,
      sync: sync,
    );
    await _repository.createDecisionFromNote(
      noteId: noteId,
      decision: decision,
    );
    return decision;
  }
}
