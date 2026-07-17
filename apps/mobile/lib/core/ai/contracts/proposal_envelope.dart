/// Side-effect-classified envelopes for AI-originated mutations.
///
/// The routing dimension is **side-effect scope**, not 'is this a
/// write?': a memo edit and a broker order are both writes but get
/// wildly different envelopes. Envelopes carry only the metadata trace
/// and proposal dispatch need; the actual application logic lives in
/// device tools and proposal appliers.
library;

sealed class ProposalEnvelope {
  const ProposalEnvelope({required this.proposalId, required this.kindLabel});

  final String proposalId;

  /// Short label for telemetry / trace ('memo_edit', 'tag_apply',
  /// 'rebalance', 'broker_order'). Free-form, not policy-bearing.
  final String kindLabel;

  /// Stable wire discriminator. Used by AiTrace and any future
  /// envelope serialization to round-trip the subtype.
  String get envelopeKind;
}

/// Pure-local, undoable mutation. Applied immediately on-device with a
/// short undo window. Examples: memo edit, tag apply, manual category
/// override, dismissed-insight flag.
final class LocalImmediateWrite extends ProposalEnvelope {
  const LocalImmediateWrite({
    required super.proposalId,
    required super.kindLabel,
    required this.summaryZh,
    required this.undo,
  });

  final String summaryZh;
  final UndoToken undo;

  @override
  String get envelopeKind => 'local_immediate';
}

class UndoToken {
  const UndoToken({required this.token, required this.expiresAtIso});
  final String token;
  final String expiresAtIso;
}

/// Generated and applied on-device, but staged for user review first.
/// Examples: batch re-categorize, draft monthly budget.
final class LocalProposal extends ProposalEnvelope {
  const LocalProposal({
    required super.proposalId,
    required super.kindLabel,
    required this.summaryZh,
    required this.payload,
  });

  final String summaryZh;
  final Map<String, Object?> payload;

  @override
  String get envelopeKind => 'local_proposal';
}

/// Touches an external system. Always typed-confirmation, always opt-in
/// on every invocation. Phase 1 carries the type only; no executors
/// are wired up.
final class ExternalSideEffect extends ProposalEnvelope {
  const ExternalSideEffect({
    required super.proposalId,
    required super.kindLabel,
    required this.summaryZh,
    required this.target,
    required this.payload,
  });

  final String summaryZh;
  final ExternalTarget target;
  final Map<String, Object?> payload;

  @override
  String get envelopeKind => 'external_side_effect';
}

class ExternalTarget {
  const ExternalTarget({required this.system, required this.endpoint});

  /// Coarse classification ('broker', 'bank', 'webhook', ...).
  final String system;

  /// Opaque identifier — never a URL or PII.
  final String endpoint;
}

/// Multiple local mutations the user wants to apply (and undo) as one
/// gesture. Wraps a non-empty list of
/// [LocalImmediateWrite] or [LocalProposal] children; mixing in any
/// [ExternalSideEffect] is rejected at construction so a single Apply
/// can never silently fire a broker order alongside memo edits.
///
/// The batch carries its own combined summary and a single
/// [BatchUndoToken] that revokes every child in reverse order.
final class BatchProposal extends ProposalEnvelope {
  BatchProposal({
    required super.proposalId,
    required super.kindLabel,
    required this.summaryZh,
    required List<ProposalEnvelope> children,
    required this.undo,
  }) : assert(children.isNotEmpty, 'BatchProposal needs at least one child'),
       children = List.unmodifiable(_rejectExternal(children));

  final String summaryZh;
  final List<ProposalEnvelope> children;
  final BatchUndoToken undo;

  @override
  String get envelopeKind => 'batch';

  static Iterable<ProposalEnvelope> _rejectExternal(
    List<ProposalEnvelope> children,
  ) {
    for (final child in children) {
      if (child is ExternalSideEffect) {
        throw ArgumentError(
          'BatchProposal does not accept ExternalSideEffect children — '
          'route each one through its own typed-confirm flow instead.',
        );
      }
      if (child is BatchProposal) {
        throw ArgumentError(
          'BatchProposal does not nest — flatten before constructing.',
        );
      }
    }
    return children;
  }
}

/// Packages multiple [UndoToken]s so the persistent undo banner can
/// revoke a batched apply with a single tap. [tokens] is stored in the
/// same order the children were applied; revert callers should walk it
/// in reverse to honour the LIFO contract of the undo stack.
class BatchUndoToken {
  const BatchUndoToken({required this.tokens, required this.expiresAtIso});

  final List<UndoToken> tokens;
  final String expiresAtIso;
}
