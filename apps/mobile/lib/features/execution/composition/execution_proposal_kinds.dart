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
  ProposalKindMeta(
    kind: 'execution_action_status_update',
    icon: FLucideIcons.listChecks,
    label: _actionStatusLabel,
    toolName: 'propose_action_status_update',
    previewRows: _actionStatusRows,
  ),
  ProposalKindMeta(
    kind: 'execution_project',
    icon: FLucideIcons.folder,
    label: _projectLabel,
    toolName: 'propose_project',
    previewRows: _projectRows,
  ),
  ProposalKindMeta(
    kind: 'execution_commitment',
    icon: FLucideIcons.target,
    label: _commitmentLabel,
    toolName: 'propose_commitment',
    previewRows: _commitmentRows,
  ),
  ProposalKindMeta(
    kind: 'execution_progress',
    icon: FLucideIcons.clipboardCheck,
    label: _progressLabel,
    toolName: 'propose_progress',
    previewRows: _progressRows,
  ),
];

Set<String> get kExecutionProposalAppliedKinds =>
    kExecutionProposalKinds.map((m) => m.kind).toSet();

String _actionLabel(AppLocalizations l10n) => l10n.executionProposalActionLabel;
String _actionStatusLabel(AppLocalizations l10n) =>
    l10n.executionProposalActionStatusLabel;
String _projectLabel(AppLocalizations l10n) =>
    l10n.executionProposalProjectLabel;
String _commitmentLabel(AppLocalizations l10n) =>
    l10n.executionProposalCommitmentLabel;
String _progressLabel(AppLocalizations l10n) =>
    l10n.executionProposalProgressLabel;

List<ProposalKindRow> _actionRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  return <ProposalKindRow>[
    ProposalKindRow(l10n.executionProposalRowAction, plan.get('title') ?? '—'),
    if (plan.get('priority') != null)
      ProposalKindRow(l10n.executionProposalRowPriority, plan.get('priority')!),
    if (plan.get('project_id') != null)
      ProposalKindRow(
        l10n.executionProposalRowProject,
        plan.get('project_id')!,
      ),
    if (plan.get('due_at') != null)
      ProposalKindRow(l10n.executionProposalRowDue, plan.get('due_at')!),
    if (plan.get('source_label') != null)
      ProposalKindRow(
        l10n.executionProposalRowSource,
        plan.get('source_label')!,
      ),
  ];
}

List<ProposalKindRow> _actionStatusRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  return <ProposalKindRow>[
    ProposalKindRow(
      l10n.executionProposalRowAction,
      plan.get('action_id') ?? '—',
    ),
    ProposalKindRow(l10n.executionStatusField, plan.get('status') ?? '—'),
    if (plan.get('progress_note') != null)
      ProposalKindRow(
        l10n.executionProposalRowProgress,
        plan.get('progress_note')!,
      ),
  ];
}

List<ProposalKindRow> _projectRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  return <ProposalKindRow>[
    ProposalKindRow(l10n.executionProposalRowProject, plan.get('title') ?? '—'),
    ..._sharedRollupRows(l10n, plan),
  ];
}

List<ProposalKindRow> _commitmentRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  return <ProposalKindRow>[
    ProposalKindRow(
      l10n.executionProposalRowCommitment,
      plan.get('title') ?? '—',
    ),
    ..._sharedRollupRows(l10n, plan),
  ];
}

List<ProposalKindRow> _progressRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  return <ProposalKindRow>[
    ProposalKindRow(l10n.executionProposalRowProgress, plan.get('note') ?? '—'),
    if (plan.get('kind') != null)
      ProposalKindRow(l10n.executionProgressKindField, plan.get('kind')!),
    if (plan.get('action_id') != null)
      ProposalKindRow(l10n.executionProposalRowAction, plan.get('action_id')!),
    if (plan.get('project_id') != null)
      ProposalKindRow(
        l10n.executionProposalRowProject,
        plan.get('project_id')!,
      ),
    if (plan.get('commitment_id') != null)
      ProposalKindRow(
        l10n.executionProposalRowCommitment,
        plan.get('commitment_id')!,
      ),
  ];
}

List<ProposalKindRow> _sharedRollupRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
) {
  return <ProposalKindRow>[
    if (plan.get('horizon') != null)
      ProposalKindRow(l10n.executionHorizonField, plan.get('horizon')!),
    if (plan.get('target_date') != null)
      ProposalKindRow(l10n.executionTargetDateField, plan.get('target_date')!),
    if (plan.get('project_id') != null)
      ProposalKindRow(
        l10n.executionProposalRowProject,
        plan.get('project_id')!,
      ),
    if (plan.get('source_label') != null)
      ProposalKindRow(
        l10n.executionProposalRowSource,
        plan.get('source_label')!,
      ),
  ];
}
