/// Finance-domain contribution to the chat rail
/// (`docs/architecture/lifeos-shell.md` §4).
///
/// The rail reads a domain-neutral `List<ChatRailContent>` from
/// `core/ai/composition/`. Finance projects persisted agent artifacts into
/// that shape so the chat surface can invoke follow-up intents without
/// importing Finance UI or data models.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/composition/chat_rail_content.dart';
import 'package:naviwealth/core/ai/composition/chat_rail_provider.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;

/// Maps FinanceOS agent artifacts into the cross-domain `ChatRailContent`
/// model the shell consumes.
List<ChatRailContent> financeChatRailContent({
  required List<AgentArtifact> artifacts,
}) {
  return artifacts
      .map(
        (artifact) => ChatRailContent(
          id: 'finance:agent_artifact:${artifact.id}',
          headline: artifact.title,
          detail: artifact.summary,
          icon: _iconForKind(artifact.kind),
          tone: _toneForSeverity(artifact.severity),
          intent: kAgentExplainResultIntent,
          object: AiObjectRef(type: kAgentArtifactObjectType, id: artifact.id),
          objectLabel: artifact.title,
          attrs: <String, Object?>{
            'artifact_id': artifact.id,
            'artifact_title': artifact.title,
            'artifact_summary': artifact.summary,
            'agent_id': artifact.agentId,
            'artifact_kind': artifact.kind.wire,
            'artifact_severity': artifact.severity.wire,
          },
          source: 'finance_agent_artifact_rail',
        ),
      )
      .toList(growable: false);
}

/// FinanceOS implementation of [ChatRailContentSelector]. Watches the
/// latest visible Finance agent artifacts and projects each one into the
/// cross-domain `ChatRailContent` shape.
///
/// Finance composition exposes this selector through its domain pack so
/// the chat surface can pick up Finance content without importing Finance
/// UI or data models.
final financeChatRailContentSelectorProvider =
    Provider<ChatRailContentSelector>((ref) {
      final artifacts =
          ref
              .watch(
                finance_agent_providers.latestFinanceAgentArtifactsProvider,
              )
              .value ??
          const <AgentArtifact>[];
      return (_) => financeChatRailContent(artifacts: artifacts);
    });

IconData _iconForKind(AgentArtifactKind kind) => switch (kind) {
  AgentArtifactKind.briefing => FLucideIcons.sun,
  AgentArtifactKind.review => FLucideIcons.clipboardCheck,
  AgentArtifactKind.alert => FLucideIcons.triangleAlert,
  AgentArtifactKind.reminder => FLucideIcons.bell,
};

ChatRailTone _toneForSeverity(AgentArtifactSeverity severity) =>
    switch (severity) {
      AgentArtifactSeverity.info => ChatRailTone.info,
      AgentArtifactSeverity.attention => ChatRailTone.warning,
      AgentArtifactSeverity.warning => ChatRailTone.danger,
    };
