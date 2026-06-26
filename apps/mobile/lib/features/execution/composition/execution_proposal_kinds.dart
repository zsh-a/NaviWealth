import 'package:forui/forui.dart';

import '../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../l10n/gen/app_localizations.dart';

const List<ProposalKindMeta> kExecutionProposalKinds = [
  ProposalKindMeta(
    kind: 'execution_action',
    icon: FLucideIcons.listTodo,
    label: _actionLabel,
    toolName: 'propose_action',
    previewRows: _actionRows,
  ),
];

Set<String> get kExecutionProposalAppliedKinds =>
    kExecutionProposalKinds.map((m) => m.kind).toSet();

String _actionLabel(AppLocalizations l10n) => l10n.executionProposalActionLabel;

List<ProposalKindRow> _actionRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  return <ProposalKindRow>[
    ProposalKindRow(l10n.executionProposalRowAction, plan.get('title') ?? '—'),
    if (plan.get('priority') != null)
      ProposalKindRow(l10n.executionProposalRowPriority, plan.get('priority')!),
    if (plan.get('due_at') != null)
      ProposalKindRow(l10n.executionProposalRowDue, plan.get('due_at')!),
    if (plan.get('source_label') != null)
      ProposalKindRow(
        l10n.executionProposalRowSource,
        plan.get('source_label')!,
      ),
  ];
}
