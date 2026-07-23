import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../persistence/app_database.dart';
import '../../contracts/memory_candidate.dart';

abstract interface class MemoryCandidateStore {
  Future<void> insert(MemoryChangeCandidate candidate);

  Future<MemoryChangeCandidate?> findById({
    required String ownerUserId,
    required String candidateId,
  });

  Future<MemoryChangeCandidate?> findByProposal({
    required String ownerUserId,
    required String proposalId,
  });

  /// Atomically reserves a pending/failed candidate for one apply attempt.
  Future<MemoryChangeCandidate?> claimForApply({
    required String ownerUserId,
    required String candidateId,
    required DateTime at,
  });

  Future<void> markApplied({
    required String ownerUserId,
    required String candidateId,
    required String? appliedMemoryId,
    required Map<String, Object?> acceptedPayload,
    required DateTime at,
  });

  Future<void> markRejected({
    required String ownerUserId,
    required String candidateId,
    required DateTime at,
  });

  Future<void> markUndone({
    required String ownerUserId,
    required String candidateId,
    required DateTime at,
  });

  Future<void> markFailed({
    required String ownerUserId,
    required String candidateId,
    required String errorMessage,
    required DateTime at,
  });

  Future<List<MemoryChangeCandidate>> listPending(String ownerUserId);
}

final class SqliteMemoryCandidateStore implements MemoryCandidateStore {
  SqliteMemoryCandidateStore({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> insert(MemoryChangeCandidate candidate) {
    return _db.customStatement(
      'INSERT INTO memory_candidates ('
      'id, proposal_id, owner_user_id, operation, status, target_memory_id, '
      'applied_memory_id, payload_json, created_at, updated_at, decided_at, '
      'error_message'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        candidate.id,
        candidate.proposalId,
        candidate.ownerUserId,
        candidate.operation.wire,
        candidate.status.wire,
        candidate.targetMemoryId,
        candidate.appliedMemoryId,
        jsonEncode(candidate.payload),
        candidate.createdAt.toUtc().millisecondsSinceEpoch,
        candidate.updatedAt.toUtc().millisecondsSinceEpoch,
        candidate.decidedAt?.toUtc().millisecondsSinceEpoch,
        candidate.errorMessage,
      ],
    );
  }

  @override
  Future<MemoryChangeCandidate?> findById({
    required String ownerUserId,
    required String candidateId,
  }) {
    return _find('id = ? AND owner_user_id = ?', <Variable<Object>>[
      Variable<Object>(candidateId),
      Variable<Object>(ownerUserId),
    ]);
  }

  @override
  Future<MemoryChangeCandidate?> findByProposal({
    required String ownerUserId,
    required String proposalId,
  }) {
    return _find('proposal_id = ? AND owner_user_id = ?', <Variable<Object>>[
      Variable<Object>(proposalId),
      Variable<Object>(ownerUserId),
    ]);
  }

  Future<MemoryChangeCandidate?> _find(
    String predicate,
    List<Variable<Object>> variables,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM memory_candidates WHERE $predicate',
          variables: variables,
        )
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<MemoryChangeCandidate?> claimForApply({
    required String ownerUserId,
    required String candidateId,
    required DateTime at,
  }) async {
    final changed = await _db.customUpdate(
      'UPDATE memory_candidates SET status = ?, updated_at = ?, '
      'error_message = NULL '
      'WHERE id = ? AND owner_user_id = ? '
      "AND status IN ('pending', 'failed')",
      variables: <Variable<Object>>[
        Variable<Object>(MemoryCandidateStatus.applying.wire),
        Variable<Object>(at.toUtc().millisecondsSinceEpoch),
        Variable<Object>(candidateId),
        Variable<Object>(ownerUserId),
      ],
    );
    if (changed != 1) return null;
    return findById(ownerUserId: ownerUserId, candidateId: candidateId);
  }

  @override
  Future<void> markApplied({
    required String ownerUserId,
    required String candidateId,
    required String? appliedMemoryId,
    required Map<String, Object?> acceptedPayload,
    required DateTime at,
  }) async {
    final changed = await _db.customUpdate(
      'UPDATE memory_candidates SET status = ?, updated_at = ?, '
      'decided_at = ?, applied_memory_id = ?, payload_json = ?, '
      'error_message = NULL '
      'WHERE id = ? AND owner_user_id = ? AND status = ?',
      variables: <Variable<Object>>[
        Variable.withString(MemoryCandidateStatus.applied.wire),
        Variable.withInt(at.toUtc().millisecondsSinceEpoch),
        Variable.withInt(at.toUtc().millisecondsSinceEpoch),
        _nullableString(appliedMemoryId),
        Variable.withString(jsonEncode(acceptedPayload)),
        Variable.withString(candidateId),
        Variable.withString(ownerUserId),
        Variable.withString(MemoryCandidateStatus.applying.wire),
      ],
    );
    if (changed != 1) {
      throw StateError('memory candidate $candidateId cannot be applied');
    }
  }

  @override
  Future<void> markRejected({
    required String ownerUserId,
    required String candidateId,
    required DateTime at,
  }) {
    return _transition(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
      from: const <MemoryCandidateStatus>{
        MemoryCandidateStatus.pending,
        MemoryCandidateStatus.failed,
      },
      to: MemoryCandidateStatus.rejected,
      at: at,
      decidedAt: at,
    );
  }

  @override
  Future<void> markUndone({
    required String ownerUserId,
    required String candidateId,
    required DateTime at,
  }) {
    return _transition(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
      from: const <MemoryCandidateStatus>{MemoryCandidateStatus.applied},
      to: MemoryCandidateStatus.undone,
      at: at,
      decidedAt: at,
    );
  }

  @override
  Future<void> markFailed({
    required String ownerUserId,
    required String candidateId,
    required String errorMessage,
    required DateTime at,
  }) {
    return _transition(
      ownerUserId: ownerUserId,
      candidateId: candidateId,
      from: const <MemoryCandidateStatus>{MemoryCandidateStatus.applying},
      to: MemoryCandidateStatus.failed,
      at: at,
      errorMessage: errorMessage,
    );
  }

  Future<void> _transition({
    required String ownerUserId,
    required String candidateId,
    required Set<MemoryCandidateStatus> from,
    required MemoryCandidateStatus to,
    required DateTime at,
    DateTime? decidedAt,
    String? appliedMemoryId,
    String? errorMessage,
  }) async {
    final placeholders = List<String>.filled(from.length, '?').join(', ');
    final variables = [
      Variable.withString(to.wire),
      Variable.withInt(at.toUtc().millisecondsSinceEpoch),
      _nullableInt(decidedAt?.toUtc().millisecondsSinceEpoch),
      _nullableString(appliedMemoryId),
      _nullableString(errorMessage),
      Variable.withString(candidateId),
      Variable.withString(ownerUserId),
      for (final status in from) Variable.withString(status.wire),
    ];
    final changed = await _db.customUpdate(
      'UPDATE memory_candidates SET status = ?, updated_at = ?, '
      'decided_at = COALESCE(?, decided_at), '
      'applied_memory_id = COALESCE(?, applied_memory_id), '
      'error_message = ? '
      'WHERE id = ? AND owner_user_id = ? '
      'AND status IN ($placeholders)',
      variables: variables,
    );
    if (changed != 1) {
      throw StateError(
        'memory candidate $candidateId cannot transition to ${to.wire}',
      );
    }
  }

  @override
  Future<List<MemoryChangeCandidate>> listPending(String ownerUserId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM memory_candidates '
          "WHERE owner_user_id = ? AND status IN ('pending', 'failed') "
          'ORDER BY created_at DESC',
          variables: <Variable<Object>>[Variable<Object>(ownerUserId)],
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  MemoryChangeCandidate _fromRow(QueryRow row) {
    final payloadRaw = jsonDecode(row.read<String>('payload_json'));
    return MemoryChangeCandidate(
      id: row.read<String>('id'),
      proposalId: row.read<String>('proposal_id'),
      ownerUserId: row.read<String>('owner_user_id'),
      operation:
          MemoryCandidateOperationWire.tryParse(
            row.read<String>('operation'),
          ) ??
          MemoryCandidateOperation.create,
      status: MemoryCandidateStatusWire.parse(row.read<String>('status')),
      targetMemoryId: row.readNullable<String>('target_memory_id'),
      appliedMemoryId: row.readNullable<String>('applied_memory_id'),
      payload: payloadRaw is Map
          ? payloadRaw.map((key, value) => MapEntry('$key', value))
          : const <String, Object?>{},
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
      decidedAt: switch (row.readNullable<int>('decided_at')) {
        final millis? => DateTime.fromMillisecondsSinceEpoch(
          millis,
          isUtc: true,
        ),
        null => null,
      },
      errorMessage: row.readNullable<String>('error_message'),
    );
  }

  static Variable<int> _nullableInt(int? value) =>
      value == null ? const Variable<int>(null) : Variable.withInt(value);

  static Variable<String> _nullableString(String? value) =>
      value == null ? const Variable<String>(null) : Variable.withString(value);
}
