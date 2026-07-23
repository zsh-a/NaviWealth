import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/memory_candidate.dart';
import 'package:naviwealth/core/ai/local/memory/memory_candidate_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

import '../../../persistence/test_database.dart';

MemoryChangeCandidate _candidate({
  String id = 'candidate-1',
  String proposalId = 'proposal-1',
  String owner = 'user-1',
}) {
  final at = DateTime.utc(2026, 7, 2);
  return MemoryChangeCandidate(
    id: id,
    proposalId: proposalId,
    ownerUserId: owner,
    operation: MemoryCandidateOperation.create,
    status: MemoryCandidateStatus.pending,
    payload: const <String, Object?>{
      'operation': 'create',
      'title': 'local first',
    },
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  group('SqliteMemoryCandidateStore', () {
    late SqliteMemoryCandidateStore store;
    late AppDatabase db;

    setUp(() {
      db = makeTestDatabase();
      store = SqliteMemoryCandidateStore(db: db);
    });

    tearDown(() => db.close());

    test('round-trips with owner isolation', () async {
      await store.insert(_candidate());

      expect(
        await store.findById(
          ownerUserId: 'other-user',
          candidateId: 'candidate-1',
        ),
        isNull,
      );
      final restored = await store.findByProposal(
        ownerUserId: 'user-1',
        proposalId: 'proposal-1',
      );
      expect(restored?.status, MemoryCandidateStatus.pending);
      expect(restored?.payload['title'], 'local first');
    });

    test('claim is atomic and accepted payload is persisted', () async {
      await store.insert(_candidate());
      final at = DateTime.utc(2026, 7, 2, 1);

      final claimed = await store.claimForApply(
        ownerUserId: 'user-1',
        candidateId: 'candidate-1',
        at: at,
      );
      expect(claimed?.status, MemoryCandidateStatus.applying);
      expect(
        await store.claimForApply(
          ownerUserId: 'user-1',
          candidateId: 'candidate-1',
          at: at,
        ),
        isNull,
      );

      await store.markApplied(
        ownerUserId: 'user-1',
        candidateId: 'candidate-1',
        appliedMemoryId: 'memory-1',
        acceptedPayload: const <String, Object?>{
          'operation': 'create',
          'title': 'edited by user',
        },
        at: at,
      );
      final applied = await store.findById(
        ownerUserId: 'user-1',
        candidateId: 'candidate-1',
      );
      expect(applied?.status, MemoryCandidateStatus.applied);
      expect(applied?.appliedMemoryId, 'memory-1');
      expect(applied?.payload['title'], 'edited by user');
      expect(applied?.decidedAt, at);
    });

    test('rejected candidates cannot be claimed', () async {
      await store.insert(_candidate());
      final at = DateTime.utc(2026, 7, 2, 2);
      await store.markRejected(
        ownerUserId: 'user-1',
        candidateId: 'candidate-1',
        at: at,
      );

      expect(
        await store.claimForApply(
          ownerUserId: 'user-1',
          candidateId: 'candidate-1',
          at: at,
        ),
        isNull,
      );
      expect(await store.listPending('user-1'), isEmpty);
    });
  });
}
