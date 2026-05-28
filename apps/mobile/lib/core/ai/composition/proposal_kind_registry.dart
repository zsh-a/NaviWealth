/// Cross-domain registry of `propose_*` kinds rendered by the chat
/// propose-card pipeline (`docs/lifeos-shell.md` §4).
///
/// Each domain contributes a [ProposalKindMeta] for every kind it
/// emits — presentation (icon / label) plus the per-kind edit field
/// list and preview row builder consumed by `propose_card.dart`. The
/// shell propose card never enumerates kinds itself; everything goes
/// through this registry, so a new domain (HealthOS, KnowledgeOS, …)
/// adds its kinds by registering more metas, no shell edits.
///
/// Default registry is empty. `bootstrap.dart` overrides
/// [proposalKindRegistryProvider] with the union of every active
/// domain's contributions.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import 'proposal_plan.dart';

/// Per-kind presentation + render hooks.
@immutable
class ProposalKindMeta {
  const ProposalKindMeta({
    required this.kind,
    required this.icon,
    required this.label,
    required this.toolName,
    this.editableFields,
    this.previewRows,
  });

  /// Wire identifier emitted by `propose_*` tools, e.g. `'trade'`.
  final String kind;

  /// Icon shown in the propose card header.
  final IconData icon;

  /// Localised label, e.g. "交易". Called at render time so the chip
  /// follows the active locale without rebuilding the registry.
  final String Function(AppLocalizations l10n) label;

  /// Matching tool name, e.g. `'propose_trade'`. Used by
  /// `interactionModeForKindLabel` and trace lookups.
  final String toolName;

  /// Optional curated editable field list rendered in the inline
  /// edit sheet. `null` falls back to "no curated fields" → the
  /// sheet promotes itself to full payload mode.
  final List<ProposalKindEditField> Function(AppLocalizations l10n)?
  editableFields;

  /// Optional preview row builder rendered in the expanded card.
  /// Receives both the [ReadyProposalPlan] and any pending overrides
  /// so per-domain formatting (currency, dates) can compose them.
  /// `null` falls back to an empty row list.
  final List<ProposalKindRow> Function(
    AppLocalizations l10n,
    ReadyProposalPlan plan,
    Map<String, Object?>? overrides,
  )?
  previewRows;
}

/// A single editable input shown in the inline edit sheet.
@immutable
class ProposalKindEditField {
  const ProposalKindEditField({
    required this.payloadKey,
    required this.label,
    this.hint,
    this.numeric = false,
  });

  final String payloadKey;
  final String label;
  final String? hint;
  final bool numeric;
}

/// A single label/value row shown in the expanded preview.
@immutable
class ProposalKindRow {
  const ProposalKindRow(this.label, this.value);
  final String label;
  final String value;
}

/// Active kind registry for the current build. Default empty.
final proposalKindRegistryProvider = Provider<List<ProposalKindMeta>>(
  (ref) => const <ProposalKindMeta>[],
);

extension ProposalKindRegistryLookup on List<ProposalKindMeta> {
  /// Returns the meta for [kind] or `null` if no domain registered it.
  ProposalKindMeta? metaFor(String kind) {
    for (final m in this) {
      if (m.kind == kind) return m;
    }
    return null;
  }
}
