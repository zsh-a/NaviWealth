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
          Text(
            artifact.summary,
            style: typography.body.sm.copyWith(height: 1.4),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

class AgentCompactResultRow extends StatelessWidget {
  const AgentCompactResultRow({
    super.key,
    required this.artifact,
    required this.metaLabel,
    this.onOpen,
  });

  final AgentArtifact artifact;
  final String metaLabel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = _accentColor(context, artifact.severity);
    return SoftCard(
      level: SoftCardLevel.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      onPress: onOpen,
      child: Row(
        children: [
          AppIconTile(
            icon: _iconForKind(artifact.kind),
            color: accent,
            size: AppSpacing.s32,
            iconSize: AppIconSizes.sm,
            backgroundOpacity: AppOpacity.subtle,
            foregroundOpacity: 1,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artifact.title,
                  style: context.captionLabelStyle,
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
          ),
          const SizedBox(width: AppSpacing.s6),
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.xs,
            color: context.theme.colors.mutedForeground,
          ),
        ],
      ),
    );
  }
}

class AgentRunStatusCard extends StatefulWidget {
  const AgentRunStatusCard({
    super.key,
    required this.record,
    required this.metaLabel,
    this.onRetry,
  });

  final AgentRunRecord record;
  final String metaLabel;
  final FutureOr<void> Function()? onRetry;

  @override
  State<AgentRunStatusCard> createState() => _AgentRunStatusCardState();
}

class _AgentRunStatusCardState extends State<AgentRunStatusCard> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying || widget.onRetry == null) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry!();
    } on Object catch (error) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(context, error),
      );
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final record = widget.record;
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
                      widget.metaLabel,
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
              widget.onRetry != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: AppQuietButton(
                label: l10n.agentResultRetryAction,
                onPress: _retrying ? null : _retry,
                busy: _retrying,
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

class AgentResultPanelStateCard extends StatelessWidget {
  const AgentResultPanelStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.error = false,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final sem = SemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    final accent = error ? sem.danger : colors.primary;
    return SoftCard(
      level: SoftCardLevel.flat,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: icon,
            color: accent,
            size: 36,
            iconSize: AppIconSizes.h18,
            backgroundOpacity: AppOpacity.subtle,
            foregroundOpacity: 1,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.labelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  message,
                  style: context.captionStyle.copyWith(height: 1.4),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                if (loading) ...[
                  const SizedBox(height: AppSpacing.s12),
                  const FCircularProgress(
                    size: FCircularProgressSizeVariant.sm,
                  ),
                ] else if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  AppQuietButton(
                    label: l10n.commonRetry,
                    onPress: onRetry,
                    prefix: const Icon(
                      FLucideIcons.refreshCw,
                      size: AppIconSizes.xs,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
    footer: _AgentArtifactSheetFooter(artifact: artifact),
  );
}

class AgentArtifactDetailBody extends ConsumerStatefulWidget {
  const AgentArtifactDetailBody({
    super.key,
    required this.artifact,
    this.onVisibilityChanged,
  });

  final AgentArtifact artifact;
  final FutureOr<void> Function()? onVisibilityChanged;

  @override
  ConsumerState<AgentArtifactDetailBody> createState() =>
      _AgentArtifactDetailBodyState();
}

class _AgentArtifactDetailBodyState
    extends ConsumerState<AgentArtifactDetailBody> {
  _VisibilityAction? _visibilityBusy;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final artifact = widget.artifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ArtifactSummary(summary: artifact.summary),
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
              for (final action in artifact.actions)
                _AgentActionTile(
                  action: action,
                  artifact: artifact,
                  onPress: action.intent == null
                      ? null
                      : () => _askAboutAction(context, ref, action),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.s16),
        _VisibilityActionsRow(
          snoozeLabel: l10n.agentResultSnoozeTitle,
          dismissLabel: l10n.agentResultDismissTitle,
          busyAction: _visibilityBusy,
          onSnooze: () => _runVisibilityAction(_VisibilityAction.snooze),
          onDismiss: () => _runVisibilityAction(_VisibilityAction.dismiss),
        ),
      ],
    );
  }

  Future<void> _runVisibilityAction(_VisibilityAction action) async {
    if (_visibilityBusy != null) return;
    setState(() => _visibilityBusy = action);
    try {
      switch (action) {
        case _VisibilityAction.snooze:
          await _snoozeAgentArtifact(
            context,
            ref,
            artifact: widget.artifact,
            onVisibilityChanged: widget.onVisibilityChanged,
          );
          break;
        case _VisibilityAction.dismiss:
          await _dismissAgentArtifact(
            context,
            ref,
            artifact: widget.artifact,
            onVisibilityChanged: widget.onVisibilityChanged,
          );
          break;
      }
    } on Object catch (error) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          operation: 'update agent result visibility',
        ),
      );
    } finally {
      if (mounted) setState(() => _visibilityBusy = null);
    }
  }

  Future<void> _askAboutAction(
    BuildContext context,
    WidgetRef ref,
    AgentAction action,
  ) {
    return _askAboutAgentAction(
      context,
      ref,
      artifact: widget.artifact,
      action: action,
    );
  }
}

class _AgentArtifactSheetFooter extends ConsumerStatefulWidget {
  const _AgentArtifactSheetFooter({required this.artifact});

  final AgentArtifact artifact;

  @override
  ConsumerState<_AgentArtifactSheetFooter> createState() =>
      _AgentArtifactSheetFooterState();
}

class _AgentArtifactSheetFooterState
    extends ConsumerState<_AgentArtifactSheetFooter> {
  bool _secondaryBusy = false;
  bool _primaryBusy = false;

  Future<void> _runAction({
    required bool primary,
    required Future<void> Function() action,
  }) async {
    if (_primaryBusy || _secondaryBusy) return;
    setState(() {
      if (primary) {
        _primaryBusy = true;
      } else {
        _secondaryBusy = true;
      }
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          if (primary) {
            _primaryBusy = false;
          } else {
            _secondaryBusy = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final artifact = widget.artifact;
    final secondaryAction = _footerActionForArtifact(l10n, artifact);
    final footerBusy = _primaryBusy || _secondaryBusy;
    return Row(
      children: [
        Expanded(
          child: _FooterActionButton(
            onPress: () => _runAction(
              primary: false,
              action: () => secondaryAction.run(context, ref),
            ),
            icon: secondaryAction.icon,
            label: secondaryAction.label,
            busy: _secondaryBusy,
            disabled: footerBusy,
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: _FooterActionButton(
            primary: true,
            onPress: () => _runAction(
              primary: true,
              action: () =>
                  _askAboutAgentArtifact(context, ref, artifact: artifact),
            ),
            icon: FLucideIcons.messageCircle,
            label: l10n.agentResultAskFollowUpTitle,
            busy: _primaryBusy,
            disabled: footerBusy,
          ),
        ),
      ],
    );
  }
}

class _ArtifactFooterAction {
  const _ArtifactFooterAction({
    required this.icon,
    required this.label,
    required this.run,
  });

  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext context, WidgetRef ref) run;
}

_ArtifactFooterAction _footerActionForArtifact(
  AppLocalizations l10n,
  AgentArtifact artifact,
) {
  for (final action in artifact.actions) {
    if (action.intent == null) continue;
    final presentation = _agentActionPresentation(l10n, action, artifact);
    return _ArtifactFooterAction(
      icon: presentation.icon,
      label: presentation.title,
      run: (context, ref) => _askAboutAgentAction(
        context,
        ref,
        artifact: artifact,
        action: action,
      ),
    );
  }
  if (artifact.evidence.isNotEmpty) {
    return _ArtifactFooterAction(
      icon: FLucideIcons.fileText,
      label: l10n.agentResultShowEvidenceTitle,
      run: (context, ref) =>
          _showEvidenceForAgentArtifact(context, ref, artifact: artifact),
    );
  }
  return _ArtifactFooterAction(
    icon: FLucideIcons.listChecks,
    label: l10n.agentResultCreatePlanTitle,
    run: (context, ref) =>
        _createPlanFromAgentArtifact(context, ref, artifact: artifact),
  );
}

class _FooterActionButton extends StatelessWidget {
  const _FooterActionButton({
    required this.icon,
    required this.label,
    required this.onPress,
    this.primary = false,
    this.busy = false,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final bool primary;
  final bool busy;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = primary ? colors.primaryForeground : colors.foreground;
    final background = primary
        ? colors.primary
        : colors.muted.withValues(alpha: AppOpacity.whisper);

    return Semantics(
      button: true,
      child: FTappable(
        onPress: busy || disabled ? null : onPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: primary
                  ? colors.primary
                  : colors.foreground.withValues(alpha: AppOpacity.light),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s10,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const FCircularProgress(size: FCircularProgressSizeVariant.sm)
                else
                  Icon(icon, size: AppIconSizes.xs, color: foreground),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.mediumLabelStyle.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _snoozeAgentArtifact(
  BuildContext context,
  WidgetRef ref, {
  required AgentArtifact artifact,
  FutureOr<void> Function()? onVisibilityChanged,
}) async {
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

Future<void> _dismissAgentArtifact(
  BuildContext context,
  WidgetRef ref, {
  required AgentArtifact artifact,
  FutureOr<void> Function()? onVisibilityChanged,
}) async {
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

Future<void> _askAboutAgentArtifact(
  BuildContext context,
  WidgetRef ref, {
  required AgentArtifact artifact,
}) {
  return askAi(
    context,
    ref,
    intent: kAgentExplainResultIntent,
    object: AiObjectRef(type: kAgentArtifactObjectType, id: artifact.id),
    objectLabel: artifact.title,
    attrs: _agentArtifactAttrs(artifact),
    source: 'agent_artifact_detail',
    capabilities: const <AiCapability>{AiCapability.chat},
  );
}

Future<void> _askAboutAgentAction(
  BuildContext context,
  WidgetRef ref, {
  required AgentArtifact artifact,
  required AgentAction action,
}) {
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
      ..._agentArtifactAttrs(artifact),
      'action_kind': action.kind,
      'action_label': action.label,
      if (action.description != null) 'action_description': action.description,
      if (action.capabilities.isNotEmpty)
        'action_capabilities': action.capabilities,
      ...action.payload,
    },
    source: 'agent_artifact_detail',
  );
}

Future<void> _showEvidenceForAgentArtifact(
  BuildContext context,
  WidgetRef ref, {
  required AgentArtifact artifact,
}) {
  return askAi(
    context,
    ref,
    intent: kAgentShowEvidenceIntent,
    object: AiObjectRef(type: kAgentArtifactObjectType, id: artifact.id),
    objectLabel: artifact.title,
    attrs: <String, Object?>{
      ..._agentArtifactAttrs(artifact),
      'follow_up_focus': 'evidence',
    },
    source: 'agent_artifact_detail',
    capabilities: const <AiCapability>{AiCapability.chat},
  );
}

Future<void> _createPlanFromAgentArtifact(
  BuildContext context,
  WidgetRef ref, {
  required AgentArtifact artifact,
}) {
  return askAi(
    context,
    ref,
    intent: kAgentCreatePlanFromResultIntent,
    object: AiObjectRef(type: kAgentArtifactObjectType, id: artifact.id),
    objectLabel: artifact.title,
    attrs: <String, Object?>{
      ..._agentArtifactAttrs(artifact),
      'follow_up_focus': 'plan',
    },
    source: 'agent_artifact_detail',
    capabilities: const <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
  );
}

Map<String, Object?> _agentArtifactAttrs(AgentArtifact artifact) {
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

class _ArtifactSummary extends StatelessWidget {
  const _ArtifactSummary({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Text(
      summary,
      style: typography.body.sm.copyWith(
        height: 1.5,
        color: colors.mutedForeground,
      ),
    );
  }
}

enum _VisibilityAction { snooze, dismiss }

class _VisibilityActionsRow extends StatelessWidget {
  const _VisibilityActionsRow({
    required this.snoozeLabel,
    required this.dismissLabel,
    required this.busyAction,
    required this.onSnooze,
    required this.onDismiss,
  });

  final String snoozeLabel;
  final String dismissLabel;
  final _VisibilityAction? busyAction;
  final VoidCallback onSnooze;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      children: [
        Expanded(
          child: _VisibilityActionButton(
            icon: FLucideIcons.clock3,
            label: snoozeLabel,
            color: colors.primary,
            busy: busyAction == _VisibilityAction.snooze,
            onPress: busyAction == null ? onSnooze : null,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: _VisibilityActionButton(
            icon: FLucideIcons.x,
            label: dismissLabel,
            color: colors.mutedForeground,
            busy: busyAction == _VisibilityAction.dismiss,
            onPress: busyAction == null ? onDismiss : null,
          ),
        ),
      ],
    );
  }
}

class _VisibilityActionButton extends StatelessWidget {
  const _VisibilityActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.busy,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool busy;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      child: FTappable(
        onPress: onPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.muted.withValues(alpha: AppOpacity.whisper),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: colors.foreground.withValues(alpha: AppOpacity.light),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: AppIconSizes.xs,
                    height: AppIconSizes.xs,
                    child: FCircularProgress(),
                  )
                else
                  Icon(icon, size: AppIconSizes.xs, color: color),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.captionLabelStyle.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.captionLabelStyle.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        ...children.expand(
          (child) => <Widget>[
            child,
            if (child != children.last) const SizedBox(height: AppSpacing.s4),
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
    this.onPress,
    this.trailingIcon,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final VoidCallback? onPress;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: AppSpacing.s32,
            height: AppSpacing.s32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: AppIconSizes.xs, color: color),
          ),
          const SizedBox(width: AppSpacing.s10),
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
                Text(
                  body,
                  style: context.captionStyle.copyWith(height: 1.35),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: AppSpacing.s8),
            Icon(
              trailingIcon,
              size: AppIconSizes.xs,
              color: colors.mutedForeground,
            ),
          ],
        ],
      ),
    );

    if (onPress == null) return content;
    return Semantics(
      button: true,
      child: FTappable(onPress: onPress, child: content),
    );
  }
}

class _AgentActionTile extends StatelessWidget {
  const _AgentActionTile({
    required this.action,
    required this.artifact,
    this.onPress,
  });

  final AgentAction action;
  final AgentArtifact artifact;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final presentation = _agentActionPresentation(
      AppLocalizations.of(context),
      action,
      artifact,
    );
    return _DetailTile(
      icon: presentation.icon,
      title: presentation.title,
      body: presentation.body,
      color: context.theme.colors.primary,
      trailingIcon: onPress == null ? null : FLucideIcons.messageCircle,
      onPress: onPress,
    );
  }
}

class _AgentActionPresentation {
  const _AgentActionPresentation({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

_AgentActionPresentation _agentActionPresentation(
  AppLocalizations l10n,
  AgentAction action,
  AgentArtifact artifact,
) {
  final title = action.label.trim().isEmpty
      ? _humanizeActionKind(action.kind)
      : action.label.trim();
  final explicitBody =
      action.description ??
      _stringPayload(action.payload, 'description') ??
      _stringPayload(action.payload, 'body');
  if (explicitBody != null && explicitBody.trim().isNotEmpty) {
    return _AgentActionPresentation(
      icon: _iconForAction(action),
      title: title,
      body: explicitBody.trim(),
    );
  }
  final knownBody = _knownActionBody(l10n, action, artifact);
  if (knownBody != null) {
    return _AgentActionPresentation(
      icon: _iconForAction(action),
      title: title,
      body: knownBody,
    );
  }
  final fallback = action.intent ?? action.kind;
  return _AgentActionPresentation(
    icon: _iconForAction(action),
    title: title,
    body: fallback.trim().isEmpty
        ? l10n.agentResultActionFallbackBody
        : l10n.agentResultActionFallbackWithKey(fallback),
  );
}

String? _stringPayload(Map<String, Object?> payload, String key) {
  final value = payload[key];
  return value is String ? value : null;
}

String? _knownActionBody(
  AppLocalizations l10n,
  AgentAction action,
  AgentArtifact artifact,
) {
  final key = '${action.kind} ${action.intent ?? ''}'.toLowerCase();
  if (key.contains('evidence')) return l10n.agentResultShowEvidenceBody;
  if (key.contains('plan') || key.contains('proposal')) {
    return l10n.agentResultCreatePlanBody;
  }
  if (key.contains('ask') || key.contains('explain')) {
    return l10n.agentResultAskFollowUpBody;
  }
  if (artifact.evidence.isNotEmpty && key.contains('review')) {
    return l10n.agentResultShowEvidenceBody;
  }
  return null;
}

IconData _iconForAction(AgentAction action) {
  final key = '${action.kind} ${action.intent ?? ''}'.toLowerCase();
  if (key.contains('evidence')) return FLucideIcons.fileText;
  if (key.contains('plan') || key.contains('proposal')) {
    return FLucideIcons.listChecks;
  }
  if (key.contains('ask') || key.contains('explain')) {
    return FLucideIcons.messageCircle;
  }
  return FLucideIcons.listChecks;
}

String _humanizeActionKind(String kind) {
  final normalized = kind.trim().replaceAll(RegExp(r'[_-]+'), ' ');
  if (normalized.isEmpty) return 'Action';
  return normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
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
    return _DetailTile(
      icon: FLucideIcons.network,
      title: title,
      body: '$body\n$traceId',
      color: colors.primary,
      trailingIcon: FLucideIcons.externalLink,
      onPress: () {
        final router = GoRouter.of(context);
        if (appSheetOverlayDepthListenable.value > 0) {
          unawaited(closeSheetThen(context, () => router.push<void>(route)));
        } else {
          unawaited(router.push<void>(route));
        }
      },
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
