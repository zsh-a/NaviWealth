/// User-reviewable staging record for AI-proposed long-term memory changes.
///
/// Candidates are local-only and have no authority until the user confirms
/// the matching ProposalEnvelope. The model never writes [MemoryRecord]
/// directly.
library;

enum MemoryCandidateOperation { create, supersede, forget }

extension MemoryCandidateOperationWire on MemoryCandidateOperation {
  String get wire => switch (this) {
    MemoryCandidateOperation.create => 'create',
    MemoryCandidateOperation.supersede => 'supersede',
    MemoryCandidateOperation.forget => 'forget',
  };

  static MemoryCandidateOperation? tryParse(String? wire) => switch (wire) {
    'create' => MemoryCandidateOperation.create,
    'supersede' => MemoryCandidateOperation.supersede,
    'forget' => MemoryCandidateOperation.forget,
    _ => null,
  };
}

enum MemoryCandidateStatus {
  pending,
  applying,
  applied,
  rejected,
  undone,
  failed,
}

extension MemoryCandidateStatusWire on MemoryCandidateStatus {
  String get wire => switch (this) {
    MemoryCandidateStatus.pending => 'pending',
    MemoryCandidateStatus.applying => 'applying',
    MemoryCandidateStatus.applied => 'applied',
    MemoryCandidateStatus.rejected => 'rejected',
    MemoryCandidateStatus.undone => 'undone',
    MemoryCandidateStatus.failed => 'failed',
  };

  static MemoryCandidateStatus parse(String wire) => switch (wire) {
    'pending' => MemoryCandidateStatus.pending,
    'applying' => MemoryCandidateStatus.applying,
    'applied' => MemoryCandidateStatus.applied,
    'rejected' => MemoryCandidateStatus.rejected,
    'undone' => MemoryCandidateStatus.undone,
    'failed' => MemoryCandidateStatus.failed,
    _ => MemoryCandidateStatus.failed,
  };
}

final class MemoryChangeCandidate {
  const MemoryChangeCandidate({
    required this.id,
    required this.proposalId,
    required this.ownerUserId,
    required this.operation,
    required this.status,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.targetMemoryId,
    this.appliedMemoryId,
    this.decidedAt,
    this.errorMessage,
  });

  final String id;
  final String proposalId;
  final String ownerUserId;
  final MemoryCandidateOperation operation;
  final MemoryCandidateStatus status;
  final String? targetMemoryId;
  final String? appliedMemoryId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? decidedAt;
  final String? errorMessage;

  MemoryChangeCandidate copyWith({
    MemoryCandidateStatus? status,
    String? appliedMemoryId,
    DateTime? updatedAt,
    DateTime? decidedAt,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MemoryChangeCandidate(
      id: id,
      proposalId: proposalId,
      ownerUserId: ownerUserId,
      operation: operation,
      status: status ?? this.status,
      targetMemoryId: targetMemoryId,
      appliedMemoryId: appliedMemoryId ?? this.appliedMemoryId,
      payload: payload,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      decidedAt: decidedAt ?? this.decidedAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
