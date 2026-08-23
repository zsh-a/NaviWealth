import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/ai/contracts/context_evidence.dart';
import 'package:naviwealth/core/ai/contracts/memory_candidate.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_access_policy.dart';
import 'package:naviwealth/core/ai/local/memory/memory_candidate_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_proposal_applier.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

import '../../../persistence/test_database.dart';

const _owner = 'user-1';
final _now = DateTime.utc(2026, 7, 3, 12);

void main() {
  group('MemoryProposalApplier', () {
    late AppDatabase db;
    late SqliteMemoryCandidateStore candidateStore;
    late SqlitePersonalProfileStore profileStore;
    late MemoryRuntime runtime;
    late MemoryProposalApplier applier;

    setUp(() {
      db = makeTestDatabase();
      candidateStore = SqliteMemoryCandidateStore(db: db);
      profileStore = SqlitePersonalProfileStore(db);
      runtime = MemoryRuntime(
        embedder: StubEmbedder(),
        memoryStore: SqliteMemoryStore(db: db),
        eventStore: SqliteEventStore(db: db),
        clock: () => _now,
      );
      applier = MemoryProposalApplier(
        ownerUserId: _owner,
        runtime: runtime,
        profileStore: profileStore,
        candidateStore: candidateStore,
        accessPolicy: MemoryAccessPolicy.allowPrefixes(const <String>[
          'user_confirmed_ai',
          'test',
        ]),
        activeProfileDomainScopes: const <String>{'finance'},
        clock: () => _now,
      );
    });

    tearDown(() => db.close());

    test('confirmed create materializes memory and undo removes it', () async {
      final payload = _createPayload();
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.create,
        payload: payload,
      );
      final plan = _plan(payload);

      final state = await applier.apply(plan);
      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedTable, kMemoryAppliedTable);
      final memory = await runtime.memoryStore.readMemory('memory-1');
      expect(memory?.summary, '用户偏好本地优先。');
      expect(memory?.confidence, 0.95);
      expect(memory?.source, 'user_confirmed_ai');

      final candidate = await candidateStore.findById(
        ownerUserId: _owner,
        candidateId: 'candidate-1',
      );
      expect(candidate?.status, MemoryCandidateStatus.applied);

      await applier.undo(state);
      expect(await runtime.memoryStore.readMemory('memory-1'), isNull);
      expect(
        (await candidateStore.findById(
          ownerUserId: _owner,
          candidateId: 'candidate-1',
        ))?.status,
        MemoryCandidateStatus.undone,
      );
    });

    test('cancel rejects candidate without writing memory', () async {
      final payload = _createPayload();
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.create,
        payload: payload,
      );

      await applier.cancel(_plan(payload));

      expect(await runtime.memoryStore.readMemory('memory-1'), isNull);
      expect(
        (await candidateStore.findById(
          ownerUserId: _owner,
          candidateId: 'candidate-1',
        ))?.status,
        MemoryCandidateStatus.rejected,
      );
    });

    test('confirmed profile candidate materializes and undoes fact', () async {
      const payload = <String, Object?>{
        'candidate_id': 'candidate-1',
        'target_type': 'profile_fact',
        'operation': 'create',
        'record_id': 'profile-fact-1',
        'profile_kind': 'constraint',
        'key': 'cash_buffer_months',
        'value': 12,
        'summary': '保留 12 个月现金缓冲。',
        'domain_scope': 'finance',
        'reason': '用户明确确认',
      };
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.create,
        targetType: MemoryCandidateTargetType.profileFact,
        payload: payload,
      );

      final state = await applier.apply(_plan(payload));

      expect(state.appliedTable, kPersonalProfileAppliedTable);
      final fact = await profileStore.read(
        ownerUserId: _owner,
        id: 'profile-fact-1',
      );
      expect(fact?.value, 12);
      expect(fact?.authority, EvidenceAuthority.userConfirmed);

      await applier.undo(state);
      expect(
        await profileStore.read(ownerUserId: _owner, id: 'profile-fact-1'),
        isNull,
      );
    });

    test('profile payload cannot be edited after staging', () async {
      const payload = <String, Object?>{
        'candidate_id': 'candidate-1',
        'target_type': 'profile_fact',
        'operation': 'create',
        'record_id': 'profile-fact-1',
        'profile_kind': 'constraint',
        'key': 'cash_buffer_months',
        'value': 12,
        'summary': '保留 12 个月现金缓冲。',
        'domain_scope': 'finance',
        'reason': '用户明确确认',
      };
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.create,
        targetType: MemoryCandidateTargetType.profileFact,
        payload: payload,
      );

      await expectLater(
        applier.apply(_plan(<String, Object?>{...payload, 'value': 24})),
        throwsA(isA<ProposalApplyException>()),
      );

      expect(
        await profileStore.read(ownerUserId: _owner, id: 'profile-fact-1'),
        isNull,
      );
    });

    test('supersede preserves prior state for undo', () async {
      final prior = _memory(id: 'old-memory', summary: '旧偏好');
      await runtime.remember(prior);
      final payload = <String, Object?>{
        ..._createPayload(),
        'operation': 'supersede',
        'target_record_id': prior.id,
        'record_id': 'new-memory',
        'summary': '新偏好',
      };
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.supersede,
        payload: payload,
        targetRecordId: prior.id,
      );

      final state = await applier.apply(_plan(payload));
      expect(
        (await runtime.memoryStore.readMemory(prior.id))?.validUntil,
        _now,
      );
      expect(
        (await runtime.memoryStore.readMemory('new-memory'))?.summary,
        '新偏好',
      );

      await applier.undo(state);
      expect(await runtime.memoryStore.readMemory('new-memory'), isNull);
      final restored = await runtime.memoryStore.readMemory(prior.id);
      expect(restored?.summary, '旧偏好');
      expect(restored?.validUntil, isNull);
    });

    test('forget removes only owned target and undo restores it', () async {
      final prior = _memory(id: 'old-memory', summary: '不再适用');
      await runtime.remember(prior);
      const payload = <String, Object?>{
        'candidate_id': 'candidate-1',
        'operation': 'forget',
        'target_type': 'memory',
        'target_record_id': 'old-memory',
        'reason': '用户明确要求忘记',
      };
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.forget,
        payload: payload,
        targetRecordId: prior.id,
      );

      final state = await applier.apply(_plan(payload));
      expect(await runtime.memoryStore.readMemory(prior.id), isNull);

      await applier.undo(state);
      expect((await runtime.memoryStore.readMemory(prior.id))?.summary, '不再适用');
    });

    test(
      'duplicate confirmation cannot consume an applied candidate',
      () async {
        final payload = _createPayload();
        await _insertCandidate(
          candidateStore,
          operation: MemoryCandidateOperation.create,
          payload: payload,
        );
        final plan = _plan(payload);

        await applier.apply(plan);

        await expectLater(
          applier.apply(plan),
          throwsA(isA<ProposalApplyException>()),
        );
        expect(
          (await runtime.memoryStore.readMemory('memory-1'))?.sourceId,
          'candidate-1',
        );
      },
    );

    test('failed candidate can be claimed again and applied', () async {
      final payload = _createPayload();
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.create,
        payload: payload,
      );
      await candidateStore.claimForApply(
        ownerUserId: _owner,
        candidateId: 'candidate-1',
        at: _now.subtract(const Duration(minutes: 1)),
      );
      await candidateStore.markFailed(
        ownerUserId: _owner,
        candidateId: 'candidate-1',
        errorMessage: 'transient',
        at: _now.subtract(const Duration(seconds: 30)),
      );

      final state = await applier.apply(_plan(payload));

      expect(state.status, ProposalApplyStatus.applied);
      expect(
        (await candidateStore.findById(
          ownerUserId: _owner,
          candidateId: 'candidate-1',
        ))?.status,
        MemoryCandidateStatus.applied,
      );
    });

    test('supersede rejects a target owned by another user', () async {
      final prior = _memory(
        id: 'other-memory',
        summary: 'other user',
        ownerUserId: 'user-2',
      );
      await runtime.remember(prior);
      final payload = <String, Object?>{
        ..._createPayload(),
        'operation': 'supersede',
        'target_record_id': prior.id,
        'record_id': 'new-memory',
      };
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.supersede,
        payload: payload,
        targetRecordId: prior.id,
      );

      await expectLater(
        applier.apply(_plan(payload)),
        throwsA(isA<ProposalApplyException>()),
      );

      expect(
        (await runtime.memoryStore.readMemory(prior.id))?.validUntil,
        isNull,
      );
      expect(await runtime.memoryStore.readMemory('new-memory'), isNull);
    });

    test(
      'immutable memory identity cannot be edited at confirmation',
      () async {
        final payload = _createPayload();
        await _insertCandidate(
          candidateStore,
          operation: MemoryCandidateOperation.create,
          payload: payload,
        );
        final modified = <String, Object?>{
          ...payload,
          'record_id': 'modified-memory',
        };

        await expectLater(
          applier.apply(_plan(modified)),
          throwsA(isA<ProposalApplyException>()),
        );

        expect(await runtime.memoryStore.readMemory('memory-1'), isNull);
        expect(await runtime.memoryStore.readMemory('modified-memory'), isNull);
      },
    );

    test('create cannot replace an existing memory destination', () async {
      await runtime.remember(
        _memory(
          id: 'memory-1',
          summary: 'belongs to another user',
          ownerUserId: 'user-2',
        ),
      );
      final payload = _createPayload();
      await _insertCandidate(
        candidateStore,
        operation: MemoryCandidateOperation.create,
        payload: payload,
      );

      await expectLater(
        applier.apply(_plan(payload)),
        throwsA(isA<ProposalApplyException>()),
      );

      final untouched = await runtime.memoryStore.readMemory('memory-1');
      expect(untouched?.ownerUserId, 'user-2');
      expect(untouched?.summary, 'belongs to another user');
    });
  });
}

Map<String, Object?> _createPayload() => const <String, Object?>{
  'candidate_id': 'candidate-1',
  'target_type': 'memory',
  'operation': 'create',
  'record_id': 'memory-1',
  'memory_kind': 'semantic',
  'title': '本地优先',
  'summary': '用户偏好本地优先。',
  'scope': '*',
  'entities': <String>['local-first'],
  'memory_payload': <String, Object?>{'statement': 'local first'},
  'importance': 0.9,
  'reason': '用户明确表达了长期偏好',
};

ReadyProposalPlan _plan(Map<String, Object?> payload) {
  return ReadyProposalPlan(
    proposalId: 'proposal-1',
    kind: kMemoryChangeProposalKind,
    summaryZh: '记忆变更',
    payload: payload,
  );
}

Future<void> _insertCandidate(
  SqliteMemoryCandidateStore store, {
  required MemoryCandidateOperation operation,
  required Map<String, Object?> payload,
  MemoryCandidateTargetType targetType = MemoryCandidateTargetType.memory,
  String? targetRecordId,
}) {
  return store.insert(
    MemoryChangeCandidate(
      id: 'candidate-1',
      proposalId: 'proposal-1',
      ownerUserId: _owner,
      operation: operation,
      targetType: targetType,
      status: MemoryCandidateStatus.pending,
      targetRecordId: targetRecordId,
      payload: payload,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
}

MemoryRecord _memory({
  required String id,
  required String summary,
  String ownerUserId = _owner,
}) {
  return MemoryRecord(
    id: id,
    kind: MemoryKind.semantic,
    authority: EvidenceAuthority.userConfirmed,
    ownerUserId: ownerUserId,
    source: 'test',
    title: id,
    summary: summary,
    payload: const <String, Object?>{},
    entities: const <String>{},
    importance: 0.8,
    confidence: 0.95,
    createdAt: _now.subtract(const Duration(days: 30)),
    updatedAt: _now.subtract(const Duration(days: 30)),
  );
}
