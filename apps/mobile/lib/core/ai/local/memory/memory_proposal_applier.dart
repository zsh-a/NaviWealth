import 'package:collection/collection.dart';

import '../../../lifeos/personal_profile/personal_profile_fact.dart';
import '../../../lifeos/personal_profile/personal_profile_store.dart';
import '../../composition/proposal_applier.dart';
import '../../composition/proposal_apply_state.dart';
import '../../composition/proposal_plan.dart';
import '../../contracts/context_evidence.dart';
import '../../contracts/memory_candidate.dart';
import '../../contracts/memory_record.dart';
import 'memory_access_policy.dart';
import 'memory_candidate_store.dart';
import 'memory_runtime.dart';

const String kMemoryChangeProposalKind = 'memory_change';
const String kMemoryAppliedTable = 'memories';
const String kPersonalProfileAppliedTable = 'personal_profile_facts';

final class MemoryProposalApplier
    implements ProposalApplier, ProposalCancellationHandler {
  MemoryProposalApplier({
    required this.ownerUserId,
    required this.runtime,
    required this.profileStore,
    required this.candidateStore,
    required this.accessPolicy,
    required this.activeProfileDomainScopes,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String ownerUserId;
  final MemoryRuntime runtime;
  final PersonalProfileStore profileStore;
  final MemoryCandidateStore candidateStore;
  final MemoryAccessPolicy accessPolicy;
  final Set<String> activeProfileDomainScopes;
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

    MemoryRecord? priorMemory;
    PersonalProfileFact? priorProfile;
    late final String appliedRecordId;
    late final String appliedTable;
    try {
      if (!const DeepCollectionEquality().equals(
        plan.payload,
        candidate.payload,
      )) {
        throw ProposalApplyException('memory proposal payload was modified');
      }
      if (plan.get('operation') != candidate.operation.wire ||
          plan.get('target_type') != candidate.targetType.wire ||
          plan.get('target_record_id') != candidate.targetRecordId) {
        throw ProposalApplyException(
          'memory proposal target or operation was modified',
        );
      }

      switch (candidate.targetType) {
        case MemoryCandidateTargetType.memory:
          appliedTable = kMemoryAppliedTable;
          switch (candidate.operation) {
            case MemoryCandidateOperation.create:
              final record = _memoryFromPlan(plan, candidate, now);
              await _ensureMemoryDestinationAvailable(record, candidate);
              await runtime.remember(record);
              appliedRecordId = record.id;
            case MemoryCandidateOperation.supersede:
              priorMemory = await _ownedMemoryTarget(candidate);
              final record = _memoryFromPlan(plan, candidate, now);
              if (record.id == priorMemory.id) {
                throw ProposalApplyException(
                  'superseding memory must use a new record_id',
                );
              }
              await _ensureMemoryDestinationAvailable(record, candidate);
              await runtime.supersede(priorMemory.id, record);
              appliedRecordId = record.id;
            case MemoryCandidateOperation.forget:
              priorMemory = await _ownedMemoryTarget(candidate);
              await runtime.forget(priorMemory.id);
              appliedRecordId = priorMemory.id;
          }
        case MemoryCandidateTargetType.profileFact:
          appliedTable = kPersonalProfileAppliedTable;
          switch (candidate.operation) {
            case MemoryCandidateOperation.create:
              final fact = _profileFromPlan(plan, candidate, now);
              await _ensureProfileDestinationAvailable(fact);
              await profileStore.create(fact);
              appliedRecordId = fact.id;
            case MemoryCandidateOperation.supersede:
              priorProfile = await _ownedProfileTarget(candidate);
              final fact = _profileFromPlan(plan, candidate, now);
              if (fact.id == priorProfile.id) {
                throw ProposalApplyException(
                  'superseding profile fact must use a new record_id',
                );
              }
              await _ensureProfileDestinationAvailable(fact);
              await profileStore.supersede(
                ownerUserId: ownerUserId,
                priorId: priorProfile.id,
                replacement: fact,
                at: now,
              );
              appliedRecordId = fact.id;
            case MemoryCandidateOperation.forget:
              priorProfile = await _ownedProfileTarget(candidate);
              await profileStore.forget(
                ownerUserId: ownerUserId,
                id: priorProfile.id,
              );
              appliedRecordId = priorProfile.id;
          }
      }

      await candidateStore.markApplied(
        ownerUserId: ownerUserId,
        candidateId: candidate.id,
        appliedRecordId: appliedRecordId,
        acceptedPayload: plan.payload,
        at: now,
      );
      return ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedEntityId: appliedRecordId,
        appliedTable: appliedTable,
        appliedAt: now,
        undoData: <String, Object?>{
          'candidate_id': candidate.id,
          'owner_user_id': ownerUserId,
          'target_type': candidate.targetType.wire,
          'operation': candidate.operation.wire,
          'applied_record_id': appliedRecordId,
          if (priorMemory != null) 'before_memory': priorMemory.toJson(),
          if (priorProfile != null) 'before_profile': priorProfile.toJson(),
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
    final targetType = MemoryCandidateTargetTypeWire.tryParse(
      undo['target_type'] as String?,
    );
    if (operation == null || targetType == null) {
      throw ProposalApplyException('invalid memory undo operation');
    }

    final appliedRecordId = undo['applied_record_id'] as String?;
    switch (targetType) {
      case MemoryCandidateTargetType.memory:
        final prior = _memoryFromUndo(undo['before_memory']);
        switch (operation) {
          case MemoryCandidateOperation.create:
            if (appliedRecordId == null) {
              throw ProposalApplyException('memory undo is missing record id');
            }
            await runtime.forget(appliedRecordId);
          case MemoryCandidateOperation.supersede:
            if (appliedRecordId == null || prior == null) {
              throw ProposalApplyException(
                'memory undo is missing prior state',
              );
            }
            await runtime.forget(appliedRecordId);
            await runtime.remember(prior);
          case MemoryCandidateOperation.forget:
            if (prior == null) {
              throw ProposalApplyException(
                'memory undo is missing prior state',
              );
            }
            await runtime.remember(prior);
        }
      case MemoryCandidateTargetType.profileFact:
        final prior = _profileFromUndo(undo['before_profile']);
        switch (operation) {
          case MemoryCandidateOperation.create:
            if (appliedRecordId == null) {
              throw ProposalApplyException('profile undo is missing record id');
            }
            await profileStore.forget(
              ownerUserId: ownerUserId,
              id: appliedRecordId,
            );
          case MemoryCandidateOperation.supersede:
            if (appliedRecordId == null || prior == null) {
              throw ProposalApplyException(
                'profile undo is missing prior state',
              );
            }
            await profileStore.forget(
              ownerUserId: ownerUserId,
              id: appliedRecordId,
            );
            await profileStore.restore(prior);
          case MemoryCandidateOperation.forget:
            if (prior == null) {
              throw ProposalApplyException(
                'profile undo is missing prior state',
              );
            }
            await profileStore.restore(prior);
        }
    }
    await candidateStore.markUndone(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
      at: _clock().toUtc(),
    );
  }

  Future<MemoryRecord> _ownedMemoryTarget(
    MemoryChangeCandidate candidate,
  ) async {
    final targetId = candidate.targetRecordId;
    if (targetId == null || targetId.isEmpty) {
      throw ProposalApplyException('target record id is required');
    }
    final prior = await runtime.memoryStore.readMemory(targetId);
    if (prior == null ||
        prior.ownerUserId != ownerUserId ||
        !accessPolicy.allowsSource(prior.source)) {
      throw ProposalApplyException('target memory was not found');
    }
    return prior;
  }

  Future<PersonalProfileFact> _ownedProfileTarget(
    MemoryChangeCandidate candidate,
  ) async {
    final targetId = candidate.targetRecordId;
    if (targetId == null || targetId.isEmpty) {
      throw ProposalApplyException('target record id is required');
    }
    final prior = await profileStore.read(
      ownerUserId: ownerUserId,
      id: targetId,
    );
    if (prior == null ||
        (prior.domainScope != null &&
            !activeProfileDomainScopes.contains(prior.domainScope))) {
      throw ProposalApplyException('target profile fact was not found');
    }
    return prior;
  }

  Future<void> _ensureMemoryDestinationAvailable(
    MemoryRecord record,
    MemoryChangeCandidate candidate,
  ) async {
    if (candidate.payload['record_id'] != record.id) {
      throw ProposalApplyException('memory proposal identity was modified');
    }
    if (await runtime.memoryStore.readMemory(record.id) != null) {
      throw ProposalApplyException('memory destination already exists');
    }
  }

  Future<void> _ensureProfileDestinationAvailable(
    PersonalProfileFact fact,
  ) async {
    final existing = await profileStore.read(
      ownerUserId: ownerUserId,
      id: fact.id,
    );
    if (existing != null) {
      throw ProposalApplyException('profile destination already exists');
    }
  }

  MemoryRecord _memoryFromPlan(
    ReadyProposalPlan plan,
    MemoryChangeCandidate candidate,
    DateTime now,
  ) {
    final recordId = plan.get('record_id');
    final kindWire = plan.get('memory_kind');
    final title = plan.get('title')?.trim();
    final summary = plan.get('summary')?.trim();
    if (recordId == null ||
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
      id: recordId,
      kind: kind,
      role: kind == MemoryKind.episodic
          ? MemoryRole.episode
          : MemoryRole.guidance,
      authority: EvidenceAuthority.userConfirmed,
      provenance: EvidenceProvenance(
        source: 'user_confirmed_ai',
        sourceId: candidate.id,
        candidateId: candidate.id,
        observedAt: now,
      ),
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
      supersedesId: candidate.targetRecordId,
      createdAt: now,
      updatedAt: now,
    );
  }

  PersonalProfileFact _profileFromPlan(
    ReadyProposalPlan plan,
    MemoryChangeCandidate candidate,
    DateTime now,
  ) {
    final recordId = plan.get('record_id');
    final kind = PersonalProfileFactKindWire.tryParse(plan.get('profile_kind'));
    final key = plan.get('key')?.trim();
    final summary = plan.get('summary')?.trim();
    if (recordId == null ||
        kind == null ||
        key == null ||
        key.isEmpty ||
        summary == null ||
        summary.isEmpty) {
      throw ProposalApplyException('profile proposal is incomplete');
    }
    final domainScope = plan.get('domain_scope');
    if (domainScope != null &&
        !activeProfileDomainScopes.contains(domainScope)) {
      throw ProposalApplyException('profile domain is not active');
    }
    final validFrom = _date(plan.payload['valid_from']) ?? now;
    final validUntil = _date(plan.payload['valid_until']);
    if (validUntil != null && !validUntil.isAfter(validFrom)) {
      throw ProposalApplyException(
        'profile valid_until must follow valid_from',
      );
    }
    return PersonalProfileFact(
      id: recordId,
      ownerUserId: ownerUserId,
      kind: kind,
      key: key,
      value: plan.payload['value'],
      summary: summary,
      domainScope: domainScope,
      authority: EvidenceAuthority.userConfirmed,
      provenance: EvidenceProvenance(
        source: 'user_confirmed_ai',
        sourceId: candidate.id,
        candidateId: candidate.id,
        observedAt: now,
      ),
      confidence: 0.95,
      confirmedAt: now,
      validFrom: validFrom,
      validUntil: validUntil,
      supersedesFactId: candidate.targetRecordId,
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

PersonalProfileFact? _profileFromUndo(Object? value) {
  if (value is! Map) return null;
  final json = value.map((key, item) => MapEntry('$key', item));
  final kind = PersonalProfileFactKindWire.tryParse(json['kind'] as String?);
  final validFrom = _date(json['valid_from']);
  final createdAt = _date(json['created_at']);
  final updatedAt = _date(json['updated_at']);
  if (kind == null ||
      validFrom == null ||
      createdAt == null ||
      updatedAt == null) {
    return null;
  }
  final provenanceRaw = json['provenance'];
  return PersonalProfileFact(
    id: json['id']! as String,
    ownerUserId: json['owner_user_id']! as String,
    kind: kind,
    key: json['key']! as String,
    value: json['value'],
    summary: json['summary']! as String,
    domainScope: json['domain_scope'] as String?,
    authority: EvidenceAuthorityWire.parse(json['authority'] as String?),
    provenance: EvidenceProvenance.fromJson(
      provenanceRaw is Map
          ? provenanceRaw.map((key, item) => MapEntry('$key', item))
          : const <String, Object?>{},
    ),
    confidence: (json['confidence']! as num).toDouble(),
    confirmedAt: _date(json['confirmed_at']),
    validFrom: validFrom,
    validUntil: _date(json['valid_until']),
    supersedesFactId: json['supersedes_fact_id'] as String?,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}
