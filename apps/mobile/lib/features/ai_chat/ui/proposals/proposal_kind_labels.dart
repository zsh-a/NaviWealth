import '../../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Localised label for a proposal kind, resolved via
/// [proposalKindRegistryProvider]. Falls back to the "unknown" label so
/// renders never crash on a domain-less build.
String proposalKindLabel(
  AppLocalizations l10n,
  List<ProposalKindMeta> registry,
  String kind,
) {
  return registry.metaFor(kind)?.label(l10n) ?? l10n.aiChatProposalKindUnknown;
}
