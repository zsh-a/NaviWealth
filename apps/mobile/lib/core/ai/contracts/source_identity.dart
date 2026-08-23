/// Stable, domain-aware identity for one source row used as AI evidence.
///
/// The row family uses the Sync v3 boundary form (`fin:...`, `health:...`,
/// `know:...`, `exec:...`) for domain rows. Infrastructure-owned local rows
/// may use a non-domain family such as `agent:agent_runs`.
library;

import '../../auth/domain_scope.dart';

class SourceIdentity {
  const SourceIdentity({
    required this.domain,
    required this.rowFamily,
    required this.rowId,
    required this.fingerprint,
  }) : assert(rowFamily != ''),
       assert(rowId != ''),
       assert(fingerprint != '');

  const SourceIdentity.infrastructure({
    required this.rowFamily,
    required this.rowId,
    required this.fingerprint,
  }) : assert(rowFamily != ''),
       assert(rowId != ''),
       assert(fingerprint != ''),
       domain = null;

  final DomainScope? domain;
  final String rowFamily;
  final String rowId;
  final String fingerprint;

  Map<String, Object?> toJson() => <String, Object?>{
    if (domain != null) 'domain': domain!.wire,
    'row_family': rowFamily,
    'row_id': rowId,
    'fingerprint': fingerprint,
  };

  factory SourceIdentity.fromJson(Map<String, Object?> json) {
    final rowFamily = json['row_family'] as String;
    final rowId = json['row_id'] as String;
    final fingerprint = json['fingerprint'] as String;
    final domainWire = json['domain'] as String?;
    final domain = domainWire == null ? null : DomainScope.tryParse(domainWire);
    return SourceIdentity(
      domain: domain,
      rowFamily: rowFamily,
      rowId: rowId,
      fingerprint: fingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceIdentity &&
      other.domain == domain &&
      other.rowFamily == rowFamily &&
      other.rowId == rowId &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(domain, rowFamily, rowId, fingerprint);
}
