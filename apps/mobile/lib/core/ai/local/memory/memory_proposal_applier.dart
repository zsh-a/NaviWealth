import '../../composition/proposal_applier.dart';
import '../../composition/proposal_apply_state.dart';
import '../../composition/proposal_plan.dart';
import '../../contracts/memory_candidate.dart';
import '../../contracts/memory_record.dart';
import 'memory_candidate_store.dart';
import 'memory_runtime.dart';

const String kMemoryChangeProposalKind = 'memory_change';
const String kMemoryAppliedTable = 'memories';

final class MemoryProposalApplier
    implements ProposalApplier, ProposalCancellationHandler {
  MemoryProposalApplier({
    required this.ownerUserId,
    required this.runtime,
    required this.candidateStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String ownerUserId;
  final MemoryRuntime runtime;
  final MemoryCandidateStore candidateStore;
  final DateTime Function() _clock;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    if (plan.kind != kMemoryChangeProposalKind) {
      throw ProposalApplyException(
        'unsupported memory proposal kind: ${plan.kind}',
      );
    }
    final candidateId = plan.get('candidate_id');
    if (candidateId == null) {
      throw ProposalApplyException('memory candidate_id is required');
    }
    final now = _clock().toUtc();
    final staged = await candidateStore.findById(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
    );
    if (staged == null || staged.proposalId != plan.proposalId) {
      throw ProposalApplyException('memory candidate does not match proposal');
    }
    final candidate = await candidateStore.claimForApply(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
      at: now,
    );
    if (candidate == null) {
      throw ProposalApplyException(
        'memory candidate is missing, rejected, or already consumed',
      );
    }

    MemoryRecord? prior;
    late final String appliedMemoryId;
    try {
      if (plan.get('operation') != candidate.operation.wire ||
          plan.get('target_memory_id') != candidate.targetMemoryId) {
        throw ProposalApplyException(
          'memory proposal operation or target was modified',
        );
      }
      switch (candidate.operation) {
        case MemoryCandidateOperation.create:
          final record = _recordFromPlan(plan, candidate, now);
          await _ensureDestinationAvailable(record, candidate);
          await runtime.remember(record);
          appliedMemoryId = record.id;
          break;
        case MemoryCandidateOperation.supersede:
          prior = await _ownedTarget(candidate);
          final record = _recordFromPlan(plan, candidate, now);
          if (record.id == prior.id) {
            throw ProposalApplyException(
              'superseding memory must use a new memory_id',
            );
          }
          await _ensureDestinationAvailable(record, candidate);
          await runtime.supersede(prior.id, record);
          appliedMemoryId = record.id;
          break;
        case MemoryCandidateOperation.forget:
          prior = await _ownedTarget(candidate);
          await runtime.forget(prior.id);
          appliedMemoryId = prior.id;
          break;
      }

      await candidateStore.markApplied(
        ownerUserId: ownerUserId,
        candidateId: candidate.id,
        appliedMemoryId: appliedMemoryId,
        acceptedPayload: plan.payload,
        at: now,
      );
      return ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedEntityId: appliedMemoryId,
        appliedTable: kMemoryAppliedTable,
        appliedAt: now,
        undoData: <String, Object?>{
          'candidate_id': candidate.id,
          'owner_user_id': ownerUserId,
          'operation': candidate.operation.wire,
          'applied_memory_id': appliedMemoryId,
          if (prior != null) 'before_memory': prior.toJson(),
        },
        shortLabel: plan.summaryZh,
      );
    } on Object catch (error) {
      try {
        await candidateStore.markFailed(
          ownerUserId: ownerUserId,
          candidateId: candidate.id,
          errorMessage: '$error',
          at: _clock().toUtc(),
        );
      } on Object {
        // Preserve the materialization error as the user-facing failure.
      }
      if (error is ProposalApplyException) rethrow;
      throw ProposalApplyException('memory change failed: $error');
    }
  }

  @override
  Future<void> cancel(ReadyProposalPlan plan) async {
    if (plan.kind != kMemoryChangeProposalKind) return;
    final candidateId = plan.get('candidate_id');
    if (candidateId == null) return;
    final candidate = await candidateStore.findById(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
    );
    if (candidate == null ||
        candidate.proposalId != plan.proposalId ||
        candidate.status == MemoryCandidateStatus.rejected) {
      return;
    }
    if (candidate.status != MemoryCandidateStatus.pending &&
        candidate.status != MemoryCandidateStatus.failed) {
      throw ProposalApplyException(
        'memory candidate can no longer be rejected',
      );
    }
    await candidateStore.markRejected(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
      at: _clock().toUtc(),
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    final undo = state.undoData;
    if (undo == null ||
        undo['owner_user_id'] != ownerUserId ||
        undo['candidate_id'] is! String) {
      throw ProposalApplyException('invalid memory undo state');
    }
    final candidateId = undo['candidate_id']! as String;
    final operation = MemoryCandidateOperationWire.tryParse(
      undo['operation'] as String?,
    );
    if (operation == null) {
      throw ProposalApplyException('invalid memory undo operation');
    }

    final appliedMemoryId = undo['applied_memory_id'] as String?;
    final prior = _memoryFromUndo(undo['before_memory']);
    switch (operation) {
      case MemoryCandidateOperation.create:
        if (appliedMemoryId == null) {
          throw ProposalApplyException('memory undo is missing memory id');
        }
        await runtime.forget(appliedMemoryId);
        break;
      case MemoryCandidateOperation.supersede:
        if (appliedMemoryId == null || prior == null) {
          throw ProposalApplyException('memory undo is missing prior state');
        }
        await runtime.forget(appliedMemoryId);
        await runtime.remember(prior);
        break;
      case MemoryCandidateOperation.forget:
        if (prior == null) {
          throw ProposalApplyException('memory undo is missing prior state');
        }
        await runtime.remember(prior);
        break;
    }
    await candidateStore.markUndone(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
      at: _clock().toUtc(),
    );
  }

  Future<MemoryRecord> _ownedTarget(MemoryChangeCandidate candidate) async {
    final targetId = candidate.targetMemoryId;
    if (targetId == null || targetId.isEmpty) {
      throw ProposalApplyException('target memory id is required');
    }
    final prior = await runtime.memoryStore.readMemory(targetId);
    if (prior == null || prior.ownerUserId != ownerUserId) {
      throw ProposalApplyException('target memory was not found');
    }
    return prior;
  }

  Future<void> _ensureDestinationAvailable(
    MemoryRecord record,
    MemoryChangeCandidate candidate,
  ) async {
    final stagedMemoryId = candidate.payload['memory_id'];
    if (stagedMemoryId is! String || stagedMemoryId != record.id) {
      throw ProposalApplyException('memory proposal identity was modified');
    }
    final existing = await runtime.memoryStore.readMemory(record.id);
    if (existing == null) return;
    final isRetryOfSameCandidate =
        existing.ownerUserId == ownerUserId &&
        existing.source == 'user_confirmed_ai' &&
        existing.sourceId == candidate.id;
    if (!isRetryOfSameCandidate) {
      throw ProposalApplyException('memory destination already exists');
    }
  }

  MemoryRecord _recordFromPlan(
    ReadyProposalPlan plan,
    MemoryChangeCandidate candidate,
    DateTime now,
  ) {
    final memoryId = plan.get('memory_id');
    final kindWire = plan.get('memory_kind');
    final title = plan.get('title')?.trim();
    final summary = plan.get('summary')?.trim();
    if (memoryId == null ||
        kindWire == null ||
        title == null ||
        title.isEmpty ||
        summary == null ||
        summary.isEmpty) {
      throw ProposalApplyException('memory proposal is incomplete');
    }
    final kind = MemoryKindWire.parse(kindWire);
    if (kind == MemoryKind.event ||
        !const <String>{
          'semantic',
          'episodic',
          'procedural',
        }.contains(kindWire)) {
      throw ProposalApplyException('unsupported user memory kind: $kindWire');
    }
    final entitiesRaw = plan.payload['entities'];
    final memoryPayloadRaw = plan.payload['memory_payload'];
    final importance = (plan.num_('importance')?.toDouble() ?? 0.8)
        .clamp(0.0, 1.0)
        .toDouble();
    final validFrom = _date(plan.payload['valid_from']) ?? now;
    final validUntil = _date(plan.payload['valid_until']);
    if (validUntil != null && !validUntil.isAfter(validFrom)) {
      throw ProposalApplyException('memory valid_until must follow valid_from');
    }
    return MemoryRecord(
      id: memoryId,
      kind: kind,
      ownerUserId: ownerUserId,
      title: title,
      summary: summary,
      payload: memoryPayloadRaw is Map
          ? memoryPayloadRaw.map((key, value) => MapEntry('$key', value))
          : const <String, Object?>{},
      entities: entitiesRaw is List
          ? entitiesRaw.whereType<String>().toSet()
          : const <String>{},
      importance: importance,
      confidence: 0.95,
      scope: plan.get('scope') ?? '*',
      source: 'user_confirmed_ai',
      sourceId: candidate.id,
      validFrom: validFrom,
      validUntil: validUntil,
      createdAt: now,
      updatedAt: now,
    );
  }
}

MemoryRecord? _memoryFromUndo(Object? value) {
  if (value is! Map) return null;
  return MemoryRecord.fromJson(
    value.map((key, item) => MapEntry('$key', item)),
  );
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}
