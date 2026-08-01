part of 'agent_result_card.dart';

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
        _ArtifactSummary(
          summary: artifact.summary,
          severity: artifact.severity,
        ),
        if (artifact.metrics.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          _MetricStrip(metrics: artifact.metrics),
        ],
        if (artifact.insights.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          _DetailSection(
            title: l10n.agentResultInsightsSection,
            children: [
              for (final insight in artifact.insights)
                _InsightEntry(
                  insight: insight,
                  artifactSeverity: artifact.severity,
                ),
            ],
          ),
        ],
        if (artifact.evidence.isNotEmpty ||
            artifact.methodology != null ||
            artifact.traceId != null) ...[
          const SizedBox(height: AppSpacing.s16),
          _EvidenceMethodAccordion(
            evidence: artifact.evidence,
            methodology: artifact.methodology,
            traceId: artifact.traceId,
            color: colors.mutedForeground,
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
}

class AgentArtifactDetailFooter extends ConsumerStatefulWidget {
  const AgentArtifactDetailFooter({super.key, required this.artifact});

  final AgentArtifact artifact;

  @override
  ConsumerState<AgentArtifactDetailFooter> createState() =>
      _AgentArtifactDetailFooterState();
}

class _AgentArtifactDetailFooterState
    extends ConsumerState<AgentArtifactDetailFooter> {
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
    final primaryAction = _footerActionForArtifact(l10n, artifact);
    final footerBusy = _primaryBusy || _secondaryBusy;
    if (primaryAction == null) {
      return _FooterActionButton(
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
      );
    }

    final isDirectNavigation = primaryAction.isDirectNavigation;
    if (!isDirectNavigation) {
      return _FooterActionButton(
        primary: true,
        onPress: () => _runAction(
          primary: true,
          action: () => primaryAction.run(context, ref),
        ),
        icon: primaryAction.icon,
        label: primaryAction.label,
        busy: _primaryBusy,
        disabled: footerBusy,
      );
    }

    return Row(
      children: [
        Expanded(
          child: _FooterActionButton(
            onPress: () => _runAction(
              primary: false,
              action: () =>
                  _askAboutAgentArtifact(context, ref, artifact: artifact),
            ),
            icon: FLucideIcons.messageCircle,
            label: l10n.agentResultAskFollowUpTitle,
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
              action: () => primaryAction.run(context, ref),
            ),
            icon: primaryAction.icon,
            label: primaryAction.label,
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
    required this.isDirectNavigation,
    required this.run,
  });

  final IconData icon;
  final String label;
  final bool isDirectNavigation;
  final Future<void> Function(BuildContext context, WidgetRef ref) run;
}

_ArtifactFooterAction? _footerActionForArtifact(
  AppLocalizations l10n,
  AgentArtifact artifact,
) {
  for (final action in artifact.actions) {
    if (action.route == null && action.intent == null) continue;
    final presentation = _agentActionPresentation(l10n, action, artifact);
    return _ArtifactFooterAction(
      icon: presentation.icon,
      label: presentation.title,
      isDirectNavigation: action.route != null,
      run: (context, ref) async {
        if (action.route case final route?) {
          _openArtifactRoute(context, route);
          return;
        }
        await _askAboutAgentAction(
          context,
          ref,
          artifact: artifact,
          action: action,
        );
      },
    );
  }
  return null;
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
      child: AppTappable(
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
  final findingStore = await ref.read(
    agent_providers.agentFindingStoreProvider.future,
  );
  await findingStore.snoozeOpenForAgent(
    ownerUserId: ownerUserId,
    agentId: artifact.agentId,
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
  final findingStore = await ref.read(
    agent_providers.agentFindingStoreProvider.future,
  );
  await findingStore.ignoreOpenForAgent(
    ownerUserId: ownerUserId,
    agentId: artifact.agentId,
    at: DateTime.now().toUtc(),
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
    if (artifact.metrics.isNotEmpty)
      'metrics': [
        for (final metric in artifact.metrics)
          <String, Object?>{
            'label': metric.label,
            'value': metric.value,
            if (metric.context != null) 'context': metric.context,
          },
      ],
    if (artifact.insights.isNotEmpty)
      'insights': [
        for (final insight in artifact.insights.take(6))
          <String, Object?>{
            if (insight.id != null) 'id': insight.id,
            'title': insight.title,
            'body': insight.body,
            if (insight.details.isNotEmpty)
              'details': [
                for (final detail in insight.details)
                  <String, Object?>{
                    'label': detail.label,
                    'value': detail.value,
                    if (detail.context != null) 'context': detail.context,
                  },
              ],
            if (insight.evidenceIds.isNotEmpty)
              'evidence_ids': insight.evidenceIds,
          },
      ],
    if (artifact.evidence.isNotEmpty)
      'evidence_refs': [
        for (final evidence in artifact.evidence.take(8))
          <String, Object?>{
            'type': evidence.type,
            'id': evidence.id,
            if (evidence.label != null) 'label': evidence.label,
            if (evidence.description != null)
              'description': evidence.description,
          },
      ],
  };
}

class _ArtifactSummary extends StatelessWidget {
  const _ArtifactSummary({required this.summary, required this.severity});

  final String summary;
  final AgentArtifactSeverity severity;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final accent = _accentColor(context, severity);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.whisper),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            const SizedBox(width: AppSpacing.s10),
            Expanded(
              child: Text(
                summary,
                style: typography.body.sm.copyWith(
                  height: 1.5,
                  color: colors.foreground,
                ),
              ),
            ),
          ],
        ),
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
      child: AppTappable(
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
