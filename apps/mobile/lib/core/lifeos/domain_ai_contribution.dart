part of 'domain_pack.dart';

/// Ai contributions owned by one domain.
final class DomainAiContribution {
  const DomainAiContribution({
    this.deviceTools = const <DeviceTool>[],
    this.assistantToolsBuilder,
    this.chatContextBuilder,
    this.toolDescriptors = const <String, ToolDescriptor>{},
    this.intentDescriptors = const <IntentDescriptor>[],
    this.proposalKinds = const <ProposalKindMeta>[],
    this.proposalApplierRouteBuilder,
    this.systemPromptBlock = '',
    this.agentBuilder,
    this.agentPresentationSpecs = const <AgentPresentationSpec>[],
    this.memorySourcePrefixes = const <String>[],
  });

  /// Device AI tools advertised when this domain is active.
  final List<DeviceTool> deviceTools;

  /// Explicit Assistant catalog. Omission exposes no conversational tools;
  /// internal agent tools stay private to the domain runtime.
  final DomainAssistantToolsBuilder? assistantToolsBuilder;

  /// Bounded domain facts passed through the shared ContextBlock channel.
  /// Detailed source data remains available through explicit domain tools.
  final DomainChatContextBuilder? chatContextBuilder;

  /// Metadata for [deviceTools], advertised when this domain is active.
  final Map<String, ToolDescriptor> toolDescriptors;

  /// AI object/capsule intents advertised when this domain is active.
  final List<IntentDescriptor> intentDescriptors;

  /// Chat proposal-card kinds advertised when this domain is active.
  final List<ProposalKindMeta> proposalKinds;

  /// Proposal apply/undo route owned by this domain. Null when the domain
  /// contributes no chat proposal-card apply kinds.
  final DomainProposalApplierRouteBuilder? proposalApplierRouteBuilder;

  /// System-prompt block appended onto [kDeviceSystemPromptBase].
  /// Empty string = no prompt contribution.
  final String systemPromptBlock;

  /// Builds the per-turn list of [Agent]s. Null when the domain has no
  /// agents. Non-null builders typically read
  /// one or more agent providers from `ref` so each agent stays
  /// composition-blind.
  final DomainAgentBuilder? agentBuilder;

  /// Shared UI presentation metadata for the agents contributed by this
  /// domain. Specs are active-domain scoped by [activeDomainPacksProvider] and
  /// keyed by [AgentPresentationSpec.agentId].
  final List<AgentPresentationSpec> agentPresentationSpecs;

  /// Memory Runtime source prefixes this domain is allowed to contribute to
  /// shared AI context. The app-level context assembler unions this field
  /// across active packs before querying both memories and recent events.
  ///
  /// This is an allow-list, not a retrieval hint: an inactive domain's local
  /// rows remain on device but must not enter an AI turn. Keep prefixes
  /// domain-owned and narrow enough that two packs cannot claim one another's
  /// records.
  final List<String> memorySourcePrefixes;
}
