/// KnowledgeOS contributions to [proposalKindRegistryProvider]
/// (`docs/lifeos-shell.md` §4, `docs/knowledgeos-domain.md` §15.6).
///
/// Presentation metadata for the KnowledgeOS `propose_*` kinds the chat
/// propose-card renders. Labels are literal strings (KnowledgeOS UI is
/// pre-l10n — §14.2 P3); the `l10n` arg is ignored. Adding a kind = one
/// entry here + one branch in `KnowledgeProposalApplier`.
library;

import 'package:forui/forui.dart';

import '../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Active KnowledgeOS kinds. `knowledge_bootstrap.dart` merges these into
/// [proposalKindRegistryProvider] alongside the other domains'.
List<ProposalKindMeta> get kKnowledgeProposalKinds => [
  ProposalKindMeta(
    kind: 'knowledge_merge',
    icon: FLucideIcons.gitMerge,
    label: (_) => '合并去重',
    toolName: 'propose_merge',
    previewRows: _mergeRows,
  ),
  ProposalKindMeta(
    kind: 'knowledge_routine',
    icon: FLucideIcons.repeat,
    label: (_) => '定期事项',
    toolName: 'propose_routine',
    previewRows: _routineRows,
  ),
  ProposalKindMeta(
    kind: 'knowledge_concept_link',
    icon: FLucideIcons.link,
    label: (_) => '概念关联',
    toolName: 'propose_concept_link',
    previewRows: _conceptLinkRows,
  ),
];

List<ProposalKindRow> _conceptLinkRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  final from = plan.get('from_concept_name') ?? plan.get('from_concept_id');
  final to = plan.get('to_concept_name') ?? plan.get('to_concept_id');
  return <ProposalKindRow>[
    if (from != null && to != null) ProposalKindRow('关联', '$from ↔ $to'),
    if (plan.get('relation') != null)
      ProposalKindRow('关系', plan.get('relation')!),
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
    ProposalKindRow('保留', (m['kept'] as String?) ?? '—'),
    if (removed is List && removed.isNotEmpty)
      ProposalKindRow('合并(软删)', removed.whereType<String>().join('、')),
    if (tags is List && tags.isNotEmpty)
      ProposalKindRow('合并后标签', tags.whereType<String>().join('、')),
  ];
}

List<ProposalKindRow> _routineRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  final interval = plan.num_('interval_days')?.toInt();
  return <ProposalKindRow>[
    ProposalKindRow('事项', plan.get('statement') ?? '—'),
    if (interval != null) ProposalKindRow('周期', '每 $interval 天'),
    if (plan.get('scope') != null) ProposalKindRow('范围', plan.get('scope')!),
  ];
}
