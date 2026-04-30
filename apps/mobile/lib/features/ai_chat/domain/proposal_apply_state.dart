/// Persistent apply state for one `propose_*` invocation.
///
/// Lives alongside the `ToolInvocation` JSON in `chat_messages` so a chat
/// reload preserves the user's confirm / cancel decisions — otherwise the
/// card would revert to "pending" every time the message timeline rebuilds.
///
/// Undo (60s after a successful apply) carries enough information to call
/// the matching repository's compensating write, captured in [undoTable]
/// and [undoRowId] for soft-delete cases or in [undoData] for valuation
/// reverts that need a previous value.
library;

enum ProposalApplyStatus {
  pending,
  applying,
  applied,
  cancelled,
  undone,
  errored,
}

extension ProposalApplyStatusX on ProposalApplyStatus {
  String get wire => switch (this) {
        ProposalApplyStatus.pending => 'pending',
        ProposalApplyStatus.applying => 'applying',
        ProposalApplyStatus.applied => 'applied',
        ProposalApplyStatus.cancelled => 'cancelled',
        ProposalApplyStatus.undone => 'undone',
        ProposalApplyStatus.errored => 'errored',
      };

  static ProposalApplyStatus parse(String s) => switch (s) {
        'pending' => ProposalApplyStatus.pending,
        'applying' => ProposalApplyStatus.applying,
        'applied' => ProposalApplyStatus.applied,
        'cancelled' => ProposalApplyStatus.cancelled,
        'undone' => ProposalApplyStatus.undone,
        'errored' => ProposalApplyStatus.errored,
        _ => ProposalApplyStatus.pending,
      };
}

class ProposalApplyState {
  const ProposalApplyState({
    required this.status,
    this.appliedEntityId,
    this.appliedTable,
    this.appliedAt,
    this.errorMessage,
    this.undoData,
    this.shortLabel,
  });

  /// Initial state for a freshly-arrived ready proposal — no user action yet.
  static const ProposalApplyState pending = ProposalApplyState(
    status: ProposalApplyStatus.pending,
  );

  final ProposalApplyStatus status;

  /// Primary key of the persisted entity (transactions.id, accounts.id,
  /// assets.id). Lets the undo path soft-delete via the same repository.
  final String? appliedEntityId;

  /// Drift table name backing [appliedEntityId]. `transactions`,
  /// `accounts`, `assets`. Captured so the undo dispatch doesn't have to
  /// re-derive it from the proposal kind.
  final String? appliedTable;

  final DateTime? appliedAt;
  final String? errorMessage;

  /// Free-form blob for kinds whose undo needs more than a row id (notably
  /// `asset_valuation`, which must restore the previous `last_price`).
  final Map<String, Object?>? undoData;

  /// One-line label rendered in the collapsed confirmed state — usually a
  /// shortened form of the plan summary. Persisted so the post-confirm
  /// row keeps showing the right text after a reload, even if the original
  /// plan summary is dropped during context truncation.
  final String? shortLabel;

  ProposalApplyState copyWith({
    ProposalApplyStatus? status,
    String? appliedEntityId,
    String? appliedTable,
    DateTime? appliedAt,
    String? errorMessage,
    Map<String, Object?>? undoData,
    String? shortLabel,
  }) {
    return ProposalApplyState(
      status: status ?? this.status,
      appliedEntityId: appliedEntityId ?? this.appliedEntityId,
      appliedTable: appliedTable ?? this.appliedTable,
      appliedAt: appliedAt ?? this.appliedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      undoData: undoData ?? this.undoData,
      shortLabel: shortLabel ?? this.shortLabel,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.wire,
        if (appliedEntityId != null) 'applied_entity_id': appliedEntityId,
        if (appliedTable != null) 'applied_table': appliedTable,
        if (appliedAt != null) 'applied_at': appliedAt!.toUtc().toIso8601String(),
        if (errorMessage != null) 'error_message': errorMessage,
        if (undoData != null) 'undo_data': undoData,
        if (shortLabel != null) 'short_label': shortLabel,
      };

  factory ProposalApplyState.fromJson(Map<String, Object?> json) {
    final at = json['applied_at'];
    final undo = json['undo_data'];
    return ProposalApplyState(
      status: ProposalApplyStatusX.parse((json['status'] ?? 'pending') as String),
      appliedEntityId: json['applied_entity_id'] as String?,
      appliedTable: json['applied_table'] as String?,
      appliedAt: at is String ? DateTime.tryParse(at) : null,
      errorMessage: json['error_message'] as String?,
      undoData: undo is Map
          ? undo.map((k, v) => MapEntry(k.toString(), v))
          : null,
      shortLabel: json['short_label'] as String?,
    );
  }

  /// Whether undo is still available — applied within the last 60 seconds.
  bool isUndoableAt(DateTime now) {
    if (status != ProposalApplyStatus.applied) return false;
    final at = appliedAt;
    if (at == null) return false;
    return now.difference(at) < const Duration(seconds: 60);
  }
}
