import '../../auth/domain_scope.dart';
import '../contracts/source_identity.dart';

/// A concrete, user-facing fact that deserves attention.
///
/// Unlike an Agent artifact, this contract describes the business item itself:
/// what changed, why it matters, the facts that support it, and where the user
/// can act. Agent run metadata intentionally does not belong here.
enum AttentionItemSeverity { info, attention, warning }

enum AttentionItemStatus { open, snoozed, resolved, ignored }

class AttentionFact {
  const AttentionFact({required this.label, required this.value});

  final String label;
  final String value;
}

class AttentionEvidence {
  const AttentionEvidence({
    required this.label,
    this.detail,
    this.source,
    this.route,
  });

  final String label;
  final String? detail;
  final SourceIdentity? source;
  final String? route;
}

class AttentionItem {
  const AttentionItem({
    required this.id,
    required this.domain,
    required this.headline,
    required this.rationale,
    this.severity = AttentionItemSeverity.attention,
    this.status = AttentionItemStatus.open,
    this.facts = const <AttentionFact>[],
    this.evidence = const <AttentionEvidence>[],
    this.route,
    this.primaryActionLabel,
    this.observedAt,
  });

  final String id;
  final DomainScope domain;
  final String headline;
  final String rationale;
  final AttentionItemSeverity severity;
  final AttentionItemStatus status;
  final List<AttentionFact> facts;
  final List<AttentionEvidence> evidence;
  final String? route;
  final String? primaryActionLabel;
  final DateTime? observedAt;
}
