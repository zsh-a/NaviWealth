/// KnowledgeOS contributions to [proposalKindRegistryProvider]
/// (`docs/architecture/lifeos-shell.md` §4, `docs/domains/knowledgeos-domain.md` §15.6).
///
/// Presentation metadata for the KnowledgeOS `propose_*` kinds the chat
/// propose-card renders. Adding a kind = one entry here + one branch in
/// `KnowledgeProposalApplier`.
library;

import 'package:forui/forui.dart';

import '../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Active KnowledgeOS kinds. `kKnowledgePack` contributes these to
/// [proposalKindRegistryProvider] alongside the other active domains.
const List<ProposalKindMeta> kKnowledgeProposalKinds = [
  ProposalKindMeta(
    kind: 'knowledge_capture',
    icon: FLucideIcons.sparkles,
    label: _captureLabel,
    toolName: 'propose_capture',
    previewRows: _captureRows,
  ),
  ProposalKindMeta(
    kind: 'knowledge_merge',
    icon: FLucideIcons.gitMerge,
    label: _mergeLabel,
    toolName: 'propose_merge',
    previewRows: _mergeRows,
  ),
];

/// Proposal kinds owned by KnowledgeOS. Derived from the same specs that
/// render proposal cards so UI registration and apply ownership cannot drift.
Set<String> get kKnowledgeProposalAppliedKinds =>
    kKnowledgeProposalKinds.map((m) => m.kind).toSet();

String _captureLabel(AppLocalizations l10n) =>
    l10n.knowledgeProposalCaptureUpgrade;
String _mergeLabel(AppLocalizations l10n) => l10n.knowledgeProposalMerge;

List<ProposalKindRow> _captureRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  final detected = plan.get('entity_type');
  final title = plan.get('title');
  return <ProposalKindRow>[
    if (detected != null)
      ProposalKindRow(l10n.knowledgeProposalRowType, detected),
    if (title != null) ProposalKindRow(l10n.knowledgeProposalRowContent, title),
  ];
}

List<ProposalKindRow> _mergeRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  final diff = plan.payload['diff'];
  if (diff is! Map) return const <ProposalKindRow>[];
  final m = diff.map((k, v) => MapEntry(k.toString(), v));
  final removed = m['removed'];
  final tags = m['merged_tags'];
  return <ProposalKindRow>[
    ProposalKindRow(
      l10n.knowledgeProposalRowKeep,
      (m['kept'] as String?) ?? '—',
    ),
    if (removed is List && removed.isNotEmpty)
      ProposalKindRow(
        l10n.knowledgeProposalRowSoftMerge,
        removed.whereType<String>().join('、'),
      ),
    if (tags is List && tags.isNotEmpty)
      ProposalKindRow(
        l10n.knowledgeProposalRowMergedTags,
        tags.whereType<String>().join('、'),
      ),
  ];
}
