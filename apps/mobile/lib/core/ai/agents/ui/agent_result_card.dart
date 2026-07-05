import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../auth/current_user.dart';
import '../../../shell/settings_route_paths.dart';
import '../../composition/ask_ai.dart';
import '../../intent/ai_intent_invocation.dart';
import '../agent_artifact.dart';
import '../agent_intents.dart';
import '../agent_run_store.dart';
import '../providers.dart' as agent_providers;

/// Domain-neutral presentation for user-visible agent output.
///
/// Domain surfaces own when to show an artifact and which actions to attach.
/// This widget only standardizes the visual shell for briefings, reviews,
/// alerts, and reminders.
class AgentResultCard extends StatelessWidget {
  const AgentResultCard({
    super.key,
    required this.artifact,
    required this.metaLabel,
    this.onOpen,
    this.footer,
    this.maxInsightPreviewCount = 2,
  });

  final AgentArtifact artifact;
  final String metaLabel;
  final VoidCallback? onOpen;
  final Widget? footer;
  final int maxInsightPreviewCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final accent = _accentColor(context, artifact.severity);
    final previewInsights = artifact.insights.take(maxInsightPreviewCount);

    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      onPress: footer == null ? onOpen : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: _iconForKind(artifact.kind),
                color: accent,
                size: 36,
                iconSize: AppIconSizes.h18,
                backgroundOpacity: AppOpacity.medium,
                foregroundOpacity: 1,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artifact.title,
                      style: context.labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      metaLabel,
                      style: context.captionStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppBadge(
                label: _badgeLabel(l10n, artifact),
                size: AppBadgeSize.compact,
                tone: _badgeTone(artifact.severity),
                icon: artifact.severity == AgentArtifactSeverity.info
                    ? null
                    : FLucideIcons.triangleAlert,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.muted.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Text(
                artifact.summary,
                style: typography.body.sm.copyWith(height: 1.45),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (artifact.insights.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s10),
            for (final insight in previewInsights) ...[
              _InsightPreview(insight: insight),
              if (insight != previewInsights.last)
                const SizedBox(height: AppSpacing.s6),
            ],
          ],
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.s12),
            footer!,
          ] else if (onOpen != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: AppQuietButton(
                label: l10n.agentResultReviewAction,
                onPress: onOpen,
                prefix: const Icon(
                  FLucideIcons.externalLink,
                  size: AppIconSizes.xs,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AgentRunStatusCard extends StatelessWidget {
  const AgentRunStatusCard({
    super.key,
    required this.record,
    required this.metaLabel,
    this.onRetry,
  });

  final AgentRunRecord record;
  final String metaLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final accent = _accentColorForRun(context, record.status);
    final summary =
        record.error ?? record.summary ?? _statusLabel(l10n, record.status);

    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: _iconForRunStatus(record.status),
                color: accent,
                size: 36,
                iconSize: AppIconSizes.h18,
                backgroundOpacity: AppOpacity.medium,
                foregroundOpacity: 1,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.agentName,
                      style: context.labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      metaLabel,
                      style: context.captionStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppBadge(
                label: _statusLabel(l10n, record.status),
                tone: _badgeToneForRun(record.status),
                size: AppBadgeSize.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.muted.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Text(
                summary,
                style: typography.body.sm.copyWith(height: 1.45),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (record.status == AgentRunLifecycleStatus.running) ...[
            const SizedBox(height: AppSpacing.s12),
            const SizedBox(
              width: AppIconSizes.sm,
              height: AppIconSizes.sm,
              child: FCircularProgress(),
            ),
          ] else if (record.status == AgentRunLifecycleStatus.failed &&
              onRetry != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: AppQuietButton(
                label: l10n.agentResultRetryAction,
                onPress: onRetry,
                prefix: const Icon(
                  FLucideIcons.refreshCw,
                  size: AppIconSizes.xs,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> showAgentArtifactSheet({
  required BuildContext context,
  required AgentArtifact artifact,
  String? subtitle,
  FutureOr<void> Function()? onVisibilityChanged,
}) {
  return showAppSheet<void>(
    context: context,
    title: artifact.title,
    subtitle:
        subtitle ??
        _artifactKindLabel(AppLocalizations.of(context), artifact.kind),
    maxHeightFactor: 0.88,
    builder: (_) => AgentArtifactDetailBody(
      artifact: artifact,
      onVisibilityChanged: onVisibilityChanged,
    ),
  );
}

class AgentArtifactDetailBody extends ConsumerWidget {
  const AgentArtifactDetailBody({
    super.key,
    required this.artifact,
    this.onVisibilityChanged,
  });

  final AgentArtifact artifact;
  final FutureOr<void> Function()? onVisibilityChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.muted.withValues(alpha: AppOpacity.subtle),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Text(
              artifact.summary,
              style: typography.body.sm.copyWith(height: 1.5),
            ),
          ),
        ),
        if (artifact.insights.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          _DetailSection(
            title: l10n.agentResultInsightsSection,
            children: [
              for (final insight in artifact.insights)
                _DetailTile(
                  icon: FLucideIcons.sparkles,
                  title: insight.title,
                  body: insight.body,
                  color: _accentColor(
                    context,
                    insight.severity ?? artifact.severity,
                  ),
                ),
            ],
          ),
        ],
        if (artifact.evidence.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          _DetailSection(
            title: l10n.agentResultEvidenceSection,
            children: [
              for (final evidence in artifact.evidence)
                _DetailTile(
                  icon: FLucideIcons.fileText,
                  title: evidence.label ?? evidence.type,
                  body: evidence.id,
                  color: colors.mutedForeground,
                ),
            ],
          ),
        ],
        if (artifact.traceId != null) ...[
          const SizedBox(height: AppSpacing.s16),
          _DetailSection(
            title: l10n.agentResultTraceSection,
            children: [
              _TraceEntryTile(
                traceId: artifact.traceId!,
                title: l10n.agentResultTraceTitle,
                body: l10n.agentResultTraceBody,
              ),
            ],
          ),
        ],
        if (artifact.actions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          _DetailSection(
            title: l10n.agentResultActionsSection,
            children: [
              ..._standardFollowUpActions(context, ref),
              ..._localVisibilityActions(context, ref),
              for (final action in artifact.actions)
                if (action.intent != null)
                  _ActionIntentTile(
                    icon: FLucideIcons.listChecks,
                    title: action.label,
                    body: action.intent!,
                    color: colors.primary,
                    onPress: () => _askAboutAction(context, ref, action),
                  )
                else
                  _DetailTile(
                    icon: FLucideIcons.listChecks,
                    title: action.label,
                    body: action.kind,
                    color: colors.primary,
                  ),
            ],
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.s16),
          _DetailSection(
            title: l10n.agentResultActionsSection,
            children: [
              ..._standardFollowUpActions(context, ref),
              ..._localVisibilityActions(context, ref),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _standardFollowUpActions(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return [
      _ActionIntentTile(
        icon: FLucideIcons.messageCircle,
        title: l10n.agentResultAskFollowUpTitle,
        body: l10n.agentResultAskFollowUpBody,
        color: colors.primary,
        onPress: () => _askAboutArtifact(context, ref),
      ),
      if (artifact.evidence.isNotEmpty)
        _ActionIntentTile(
          icon: FLucideIcons.fileText,
          title: l10n.agentResultShowEvidenceTitle,
          body: l10n.agentResultShowEvidenceBody,
          color: colors.primary,
          onPress: () => _showEvidenceForArtifact(context, ref),
        ),
      _ActionIntentTile(
        icon: FLucideIcons.listChecks,
        title: l10n.agentResultCreatePlanTitle,
        body: l10n.agentResultCreatePlanBody,
        color: colors.primary,
        onPress: () => _createPlanFromArtifact(context, ref),
      ),
    ];
  }

  List<Widget> _localVisibilityActions(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return [
      _LocalActionTile(
        icon: FLucideIcons.clock3,
        title: l10n.agentResultSnoozeTitle,
        body: l10n.agentResultSnoozeBody,
        color: colors.primary,
        actionLabel: l10n.agentResultSnoozeAction,
        onPress: () => unawaited(_snoozeArtifact(context, ref)),
      ),
      _LocalActionTile(
        icon: FLucideIcons.x,
        title: l10n.agentResultDismissTitle,
        body: l10n.agentResultDismissBody,
        color: colors.mutedForeground,
        actionLabel: l10n.agentResultDismissAction,
        onPress: () => unawaited(_dismissArtifact(context, ref)),
      ),
    ];
  }

  Future<void> _snoozeArtifact(BuildContext context, WidgetRef ref) async {
    final ownerUserId = await ref.read(currentUserIdProvider)();
    final store = await ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await store.snooze(
      ownerUserId: ownerUserId,
      id: artifact.id,
      until: DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    await onVisibilityChanged?.call();
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _dismissArtifact(BuildContext context, WidgetRef ref) async {
    final ownerUserId = await ref.read(currentUserIdProvider)();
    final store = await ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await store.dismiss(
      ownerUserId: ownerUserId,
      id: artifact.id,
      dismissedAt: DateTime.now().toUtc(),
    );
    await onVisibilityChanged?.call();
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _askAboutArtifact(BuildContext context, WidgetRef ref) {
    return askAi(
      context,
      ref,
      intent: kAgentExplainResultIntent,
      object: AiObjectRef(type: kAgentArtifactObjectType, id: artifact.id),
      objectLabel: artifact.title,
      attrs: _artifactAttrs(),
      source: 'agent_artifact_detail',
      capabilities: const <AiCapability>{AiCapability.chat},
    );
  }

  Future<void> _showEvidenceForArtifact(BuildContext context, WidgetRef ref) {
    return askAi(
      context,
      ref,
      intent: kAgentShowEvidenceIntent,
      object: AiObjectRef(type: kAgentArtifactObjectType, id: artifact.id),
      objectLabel: artifact.title,
      attrs: <String, Object?>{
        ..._artifactAttrs(),
        'follow_up_focus': 'evidence',
      },
      source: 'agent_artifact_detail',
      capabilities: const <AiCapability>{AiCapability.chat},
    );
  }

  Future<void> _createPlanFromArtifact(BuildContext context, WidgetRef ref) {
    return askAi(
      context,
      ref,
      intent: kAgentCreatePlanFromResultIntent,
      object: AiObjectRef(type: kAgentArtifactObjectType, id: artifact.id),
      objectLabel: artifact.title,
      attrs: <String, Object?>{..._artifactAttrs(), 'follow_up_focus': 'plan'},
      source: 'agent_artifact_detail',
      capabilities: const <AiCapability>{
        AiCapability.chat,
        AiCapability.proposal,
      },
    );
  }

  Future<void> _askAboutAction(
    BuildContext context,
    WidgetRef ref,
    AgentAction action,
  ) {
    return askAi(
      context,
      ref,
      intent: action.intent,
      object: AiObjectRef(
        type: action.objectType ?? kAgentArtifactObjectType,
        id: action.objectId ?? artifact.id,
      ),
      objectLabel: artifact.title,
      attrs: <String, Object?>{
        ..._artifactAttrs(),
        'action_kind': action.kind,
        'action_label': action.label,
        ...action.payload,
      },
      source: 'agent_artifact_detail',
    );
  }

  Map<String, Object?> _artifactAttrs() {
    return <String, Object?>{
      'artifact_id': artifact.id,
      'agent_id': artifact.agentId,
      'artifact_domain': artifact.domain,
      'artifact_kind': artifact.kind.wire,
      'artifact_severity': artifact.severity.wire,
      'artifact_summary': artifact.summary,
      if (artifact.memoryId != null) 'memory_id': artifact.memoryId,
      if (artifact.traceId != null) 'trace_id': artifact.traceId,
      if (artifact.insights.isNotEmpty)
        'insight_titles': [
          for (final insight in artifact.insights.take(6)) insight.title,
        ],
      if (artifact.evidence.isNotEmpty)
        'evidence_refs': [
          for (final evidence in artifact.evidence.take(8))
            <String, Object?>{
              'type': evidence.type,
              'id': evidence.id,
              if (evidence.label != null) 'label': evidence.label,
            },
        ],
    };
  }
}

class _InsightPreview extends StatelessWidget {
  const _InsightPreview({required this.insight});

  final AgentInsight insight;

  @override
  Widget build(BuildContext context) {
    final color = _accentColor(
      context,
      insight.severity ?? AgentArtifactSeverity.info,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s4),
          child: Icon(
            FLucideIcons.sparkles,
            size: AppIconSizes.xs,
            color: color,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                insight.title,
                style: context.captionLabelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                insight.body,
                style: context.captionStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.labelStyle),
        const SizedBox(height: AppSpacing.s8),
        ...children.expand(
          (child) => <Widget>[
            child,
            if (child != children.last) const SizedBox(height: AppSpacing.s8),
          ],
        ),
      ],
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppIconSizes.h18, color: color),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.captionLabelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(body, style: context.captionStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionIntentTile extends StatelessWidget {
  const _ActionIntentTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.onPress,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppIconSizes.h18, color: color),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.captionLabelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(body, style: context.captionStyle),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            AppQuietButton(
              label: l10n.agentResultAskAction,
              onPress: onPress,
              prefix: const Icon(
                FLucideIcons.messageCircle,
                size: AppIconSizes.xs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalActionTile extends StatelessWidget {
  const _LocalActionTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.actionLabel,
    required this.onPress,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final String actionLabel;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppIconSizes.h18, color: color),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.captionLabelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(body, style: context.captionStyle),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            AppQuietButton(
              label: actionLabel,
              onPress: onPress,
              prefix: Icon(icon, size: AppIconSizes.xs),
            ),
          ],
        ),
      ),
    );
  }
}

class _TraceEntryTile extends StatelessWidget {
  const _TraceEntryTile({
    required this.traceId,
    required this.title,
    required this.body,
  });

  final String traceId;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final route = SettingsRoutes.aiTransparencyDetail(traceId);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              FLucideIcons.network,
              size: AppIconSizes.h18,
              color: colors.primary,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.captionLabelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(body, style: context.captionStyle),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    traceId,
                    style: context.captionStyle.copyWith(
                      color: colors.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            AppQuietButton(
              label: AppLocalizations.of(context).agentResultTraceAction,
              onPress: () {
                final router = GoRouter.of(context);
                if (appSheetOverlayDepthListenable.value > 0) {
                  unawaited(
                    closeSheetThen(context, () => router.push<void>(route)),
                  );
                } else {
                  unawaited(router.push<void>(route));
                }
              },
              prefix: const Icon(
                FLucideIcons.externalLink,
                size: AppIconSizes.xs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconForKind(AgentArtifactKind kind) => switch (kind) {
  AgentArtifactKind.briefing => FLucideIcons.sun,
  AgentArtifactKind.review => FLucideIcons.clipboardCheck,
  AgentArtifactKind.alert => FLucideIcons.triangleAlert,
  AgentArtifactKind.reminder => FLucideIcons.bell,
};

String _artifactKindLabel(AppLocalizations l10n, AgentArtifactKind kind) =>
    switch (kind) {
      AgentArtifactKind.briefing => l10n.agentResultKindBriefing,
      AgentArtifactKind.review => l10n.agentResultKindReview,
      AgentArtifactKind.alert => l10n.agentResultKindAlert,
      AgentArtifactKind.reminder => l10n.agentResultKindReminder,
    };

String _badgeLabel(AppLocalizations l10n, AgentArtifact artifact) =>
    switch (artifact.severity) {
      AgentArtifactSeverity.info => _artifactKindLabel(l10n, artifact.kind),
      AgentArtifactSeverity.attention => l10n.agentResultSeverityAttention,
      AgentArtifactSeverity.warning => l10n.agentResultSeverityWarning,
    };

AppBadgeTone _badgeTone(AgentArtifactSeverity severity) => switch (severity) {
  AgentArtifactSeverity.info => AppBadgeTone.accent,
  AgentArtifactSeverity.attention => AppBadgeTone.warning,
  AgentArtifactSeverity.warning => AppBadgeTone.error,
};

Color _accentColor(BuildContext context, AgentArtifactSeverity severity) {
  final colors = context.theme.colors;
  final semantic = SemanticColors.of(context);
  return switch (severity) {
    AgentArtifactSeverity.info => colors.primary,
    AgentArtifactSeverity.attention => semantic.warning,
    AgentArtifactSeverity.warning => semantic.danger,
  };
}

IconData _iconForRunStatus(AgentRunLifecycleStatus status) => switch (status) {
  AgentRunLifecycleStatus.running => FLucideIcons.loaderCircle,
  AgentRunLifecycleStatus.noFinding => FLucideIcons.circleCheck,
  AgentRunLifecycleStatus.ready => FLucideIcons.sparkles,
  AgentRunLifecycleStatus.failed => FLucideIcons.triangleAlert,
};

String _statusLabel(AppLocalizations l10n, AgentRunLifecycleStatus status) =>
    switch (status) {
      AgentRunLifecycleStatus.running => l10n.agentRunStatusRunning,
      AgentRunLifecycleStatus.noFinding => l10n.agentRunStatusNoFinding,
      AgentRunLifecycleStatus.ready => l10n.agentRunStatusReady,
      AgentRunLifecycleStatus.failed => l10n.agentRunStatusFailed,
    };

AppBadgeTone _badgeToneForRun(AgentRunLifecycleStatus status) =>
    switch (status) {
      AgentRunLifecycleStatus.running => AppBadgeTone.info,
      AgentRunLifecycleStatus.noFinding => AppBadgeTone.neutral,
      AgentRunLifecycleStatus.ready => AppBadgeTone.accent,
      AgentRunLifecycleStatus.failed => AppBadgeTone.error,
    };

Color _accentColorForRun(BuildContext context, AgentRunLifecycleStatus status) {
  final colors = context.theme.colors;
  final semantic = SemanticColors.of(context);
  return switch (status) {
    AgentRunLifecycleStatus.running => semantic.info,
    AgentRunLifecycleStatus.noFinding => colors.mutedForeground,
    AgentRunLifecycleStatus.ready => colors.primary,
    AgentRunLifecycleStatus.failed => semantic.danger,
  };
}
