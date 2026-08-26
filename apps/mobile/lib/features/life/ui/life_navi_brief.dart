import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_routes.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/ui/agent_results_panel.dart';
import '../../../core/ai/composition/ask_ai.dart';
import '../../../core/ai/intent/ai_intent_invocation.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Inline Daily Navigator result for the Life hub hero.
///
/// This intentionally stays inside the existing hero surface. The overview
/// should feel like one calm intelligence layer, not a second dashboard made
/// from nested result cards.
class LifeNaviBrief extends ConsumerWidget {
  const LifeNaviBrief({super.key, required this.artifactAsync});

  final AsyncValue<AgentArtifact?> artifactAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (artifactAsync.isLoading && !artifactAsync.hasValue) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.s16),
        child: _LifeNaviBriefLoading(),
      );
    }

    final artifact = artifactAsync.value;
    if (artifact == null) return const SizedBox.shrink();

    return _LifeNaviBriefResult(artifact: artifact);
  }
}

class _LifeNaviBriefResult extends ConsumerWidget {
  const _LifeNaviBriefResult({required this.artifact});

  final AgentArtifact artifact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accent = _accentColor(context, artifact.severity);
    final insight = artifact.insights.isEmpty ? null : artifact.insights.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.s16),
        Divider(color: context.theme.colors.border, height: 1),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.agentResultKindBriefing,
                    style: context.captionLabelStyle.copyWith(color: accent),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    agentResultMetaLabel(l10n, artifact.createdAt),
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            if (artifact.evidence.isNotEmpty)
              AppBadge(
                label: l10n.agentResultEvidenceCount(artifact.evidence.length),
                tone: _badgeTone(artifact.severity),
                size: AppBadgeSize.compact,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s10),
        Text(
          artifact.summary,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: context.bodyCaptionStyle.copyWith(height: 1.45),
        ),
        if (insight != null) ...[
          const SizedBox(height: AppSpacing.s10),
          _LifeNaviInsight(insight: insight, accent: accent),
        ],
        const SizedBox(height: AppSpacing.s12),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            AppQuietButton(
              label: l10n.agentResultReviewAction,
              prefix: const Icon(FLucideIcons.externalLink),
              onPress: () =>
                  context.push(AgentArtifactRoutes.detail(artifact.id)),
            ),
            AppQuietButton(
              label: l10n.agentResultAskAction,
              prefix: const Icon(FLucideIcons.messageCircle),
              onPress: () => unawaited(_askAboutArtifact(context, ref)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _askAboutArtifact(BuildContext context, WidgetRef ref) {
    return askAi(
      context,
      ref,
      intent: kAgentExplainResultIntent,
      object: AiObjectRef(type: kAgentArtifactObjectType, id: artifact.id),
      objectLabel: artifact.title,
      attrs: <String, Object?>{
        'agent_id': artifact.agentId,
        'artifact_kind': artifact.kind.wire,
        'severity': artifact.severity.wire,
      },
      source: 'life_home_navi_brief',
      capabilities: const <AiCapability>{AiCapability.chat},
    );
  }
}

class _LifeNaviInsight extends StatelessWidget {
  const _LifeNaviInsight({required this.insight, required this.accent});

  final AgentInsight insight;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: AppOpacity.faint),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: Icon(
                FLucideIcons.lightbulb,
                size: AppIconSizes.sm,
                color: accent,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(insight.title, style: context.captionLabelStyle),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    insight.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LifeNaviBriefLoading extends StatelessWidget {
  const _LifeNaviBriefLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 104, height: 12, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(width: double.infinity, height: 14, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.s6),
        SkeletonBox(width: 220, height: 14, radius: AppRadius.sm),
      ],
    );
  }
}

Color _accentColor(BuildContext context, AgentArtifactSeverity severity) =>
    switch (severity) {
      AgentArtifactSeverity.warning => context.appTheme.status.danger.fg,
      AgentArtifactSeverity.attention => context.appTheme.status.warning.fg,
      AgentArtifactSeverity.info => context.theme.colors.primary,
    };

AppBadgeTone _badgeTone(AgentArtifactSeverity severity) => switch (severity) {
  AgentArtifactSeverity.warning => AppBadgeTone.error,
  AgentArtifactSeverity.attention => AppBadgeTone.warning,
  AgentArtifactSeverity.info => AppBadgeTone.accent,
};
