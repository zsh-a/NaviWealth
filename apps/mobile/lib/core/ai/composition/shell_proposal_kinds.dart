import 'package:forui/forui.dart';

import '../../../l10n/gen/app_localizations.dart';
import 'proposal_kind_registry.dart';

/// Cross-domain proposal kinds owned by the LifeOS shell.
const List<ProposalKindMeta> kShellProposalKinds = <ProposalKindMeta>[
  ProposalKindMeta(
    kind: 'memory_change',
    icon: FLucideIcons.brainCircuit,
    label: _memoryLabel,
    toolName: 'propose_memory',
  ),
];

String _memoryLabel(AppLocalizations l10n) => l10n.dataManagementMemoryRows;
