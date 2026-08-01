part of 'agent_result_card.dart';

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

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.metrics});

  final List<AgentMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final visible = metrics.take(3).toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.whisper),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: colors.border.withValues(alpha: AppOpacity.medium),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < visible.length; index++) ...[
              if (index > 0)
                Container(
                  width: 1,
                  height: 44,
                  color: colors.border.withValues(alpha: AppOpacity.medium),
                ),
              Expanded(child: _MetricCell(metric: visible[index])),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final AgentMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final valueColor = metric.severity == null
        ? colors.foreground
        : _accentColor(context, metric.severity!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.value,
            style: context.strongTitleStyle.copyWith(color: valueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            metric.label,
            style: context.captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (metric.context case final contextLabel?) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              contextLabel,
              style: context.microCaptionStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightEntry extends StatelessWidget {
  const _InsightEntry({required this.insight, required this.artifactSeverity});

  final AgentInsight insight;
  final AgentArtifactSeverity artifactSeverity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _accentColor(context, insight.severity ?? artifactSeverity);
    final expandable =
        insight.details.isNotEmpty ||
        insight.evidenceIds.isNotEmpty ||
        insight.route != null;
    final title = _DetailTile(
      icon: FLucideIcons.sparkles,
      title: insight.title,
      body: insight.body,
      color: color,
    );
    if (!expandable) return title;
    return FAccordion(
      children: [
        FAccordionItem(
          title: title,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s40,
              0,
              AppSpacing.s4,
              AppSpacing.s10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (insight.details.isNotEmpty)
                  _MetricDetails(metrics: insight.details),
                if (insight.evidenceIds.isNotEmpty) ...[
                  if (insight.details.isNotEmpty)
                    const SizedBox(height: AppSpacing.s8),
                  Text(
                    l10n.agentResultEvidenceSupportCount(
                      insight.evidenceIds.length,
                    ),
                    style: context.captionStyle,
                  ),
                ],
                if (insight.route case final route?) ...[
                  const SizedBox(height: AppSpacing.s8),
                  AppQuietButton(
                    label: l10n.agentResultOpenRelatedPage,
                    onPress: () => _openArtifactRoute(context, route),
                    prefix: const Icon(
                      FLucideIcons.externalLink,
                      size: AppIconSizes.xs,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricDetails extends StatelessWidget {
  const _MetricDetails({required this.metrics});

  final List<AgentMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      children: [
        for (final metric in metrics)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(metric.label, style: context.captionStyle),
                ),
                const SizedBox(width: AppSpacing.s12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        metric.value,
                        style: context.captionLabelStyle.copyWith(
                          color: metric.severity == null
                              ? colors.foreground
                              : _accentColor(context, metric.severity!),
                        ),
                        textAlign: TextAlign.end,
                      ),
                      if (metric.context case final contextLabel?)
                        Text(
                          contextLabel,
                          style: context.captionStyle,
                          textAlign: TextAlign.end,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EvidenceMethodAccordion extends ConsumerWidget {
  const _EvidenceMethodAccordion({
    required this.evidence,
    required this.methodology,
    required this.traceId,
    required this.color,
  });

  final List<AgentEvidenceRef> evidence;
  final AgentMethodology? methodology;
  final String? traceId;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FAccordion(
      children: [
        FAccordionItem(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.agentResultEvidenceMethodSection,
                  style: context.captionLabelStyle,
                ),
              ),
              if (evidence.isNotEmpty)
                AppBadge(
                  label: l10n.agentResultEvidenceCount(evidence.length),
                  size: AppBadgeSize.compact,
                  tone: AppBadgeTone.neutral,
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (methodology case final method?) ...[
                  _DetailTile(
                    icon: FLucideIcons.binary,
                    title: method.title,
                    body: method.body,
                    color: color,
                  ),
                  if (method.details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s40,
                        0,
                        AppSpacing.s4,
                        AppSpacing.s8,
                      ),
                      child: _MetricDetails(metrics: method.details),
                    ),
                ],
                for (final evidenceRef in evidence) ...[
                  _DetailTile(
                    icon: FLucideIcons.fileText,
                    title: evidenceRef.label ?? l10n.agentResultEvidenceSection,
                    body:
                        evidenceRef.description ??
                        l10n.agentResultEvidenceAvailableBody,
                    color: color,
                    trailingIcon: evidenceRef.route == null
                        ? null
                        : FLucideIcons.externalLink,
                    onPress: evidenceRef.route == null
                        ? null
                        : () => _openEvidenceRoute(
                            context,
                            evidenceRef.route!,
                            record: (succeeded) => _recordEvidenceNavigation(
                              ref,
                              succeeded: succeeded,
                            ),
                          ),
                  ),
                  if (evidenceRef.details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s40,
                        0,
                        AppSpacing.s4,
                        AppSpacing.s8,
                      ),
                      child: _MetricDetails(metrics: evidenceRef.details),
                    ),
                ],
                if (traceId case final id?)
                  _TraceEntryTile(
                    traceId: id,
                    title: l10n.agentResultTechnicalDetailsTitle,
                    body: l10n.agentResultTechnicalDetailsBody,
                  ),
              ],
            ),
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
      child: AppTappable(onPress: onPress, child: content),
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
      body: body,
      color: colors.primary,
      trailingIcon: FLucideIcons.externalLink,
      onPress: () => _openArtifactRoute(context, route),
    );
  }
}

void _openArtifactRoute(BuildContext context, String route) {
  final router = GoRouter.of(context);
  if (appSheetOverlayDepthListenable.value > 0) {
    unawaited(closeSheetThen(context, () => router.push<void>(route)));
  } else {
    unawaited(router.push<void>(route));
  }
}

void _openEvidenceRoute(
  BuildContext context,
  String route, {
  required void Function(bool succeeded) record,
}) {
  final router = GoRouter.of(context);

  void push() {
    try {
      unawaited(router.push<void>(route));
      record(true);
    } on Object {
      record(false);
      rethrow;
    }
  }

  if (appSheetOverlayDepthListenable.value > 0) {
    unawaited(closeSheetThen(context, push));
  } else {
    push();
  }
}

void _recordEvidenceNavigation(WidgetRef ref, {required bool succeeded}) {
  unawaited(
    ref
        .read(agent_providers.agentEvidenceNavigationStoreProvider.future)
        .then(
          (store) => store.record(
            occurredAt: DateTime.now().toUtc(),
            succeeded: succeeded,
          ),
        )
        .onError((_, _) {}),
  );
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
  final status = context.appTheme.status;
  return switch (severity) {
    AgentArtifactSeverity.info => colors.primary,
    AgentArtifactSeverity.attention => status.warning.fg,
    AgentArtifactSeverity.warning => status.danger.fg,
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
  final appStatus = context.appTheme.status;
  return switch (status) {
    AgentRunLifecycleStatus.running => appStatus.info.fg,
    AgentRunLifecycleStatus.noFinding => colors.mutedForeground,
    AgentRunLifecycleStatus.ready => colors.primary,
    AgentRunLifecycleStatus.failed => appStatus.danger.fg,
  };
}
