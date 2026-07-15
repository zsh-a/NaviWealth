part of 'health_today_page.dart';

class _BriefingPanel extends ConsumerStatefulWidget {
  const _BriefingPanel();

  @override
  ConsumerState<_BriefingPanel> createState() => _BriefingPanelState();
}

class _BriefingPanelState extends ConsumerState<_BriefingPanel> {
  bool _running = false;
  Object? _errorMessage;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _errorMessage = null;
    });
    try {
      // ignore: unused_result
      ref.refresh(health_agent_providers.manualMorningBriefingRunProvider);
      await ref.read(
        health_agent_providers.manualMorningBriefingRunProvider.future,
      );
      ref.invalidate(health_agent_providers.latestMorningBriefingProvider);
      ref.invalidate(
        health_agent_providers.latestMorningBriefingArtifactProvider,
      );
    } on Object catch (e) {
      setState(() => _errorMessage = e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artifactAsync = ref.watch(
      health_agent_providers.latestMorningBriefingArtifactProvider,
    );
    final memoryAsync = ref.watch(
      health_agent_providers.latestMorningBriefingProvider,
    );
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);

    // Quiet while loading — no skeleton on the signal surface.
    if ((artifactAsync.isLoading && !artifactAsync.hasValue) ||
        (artifactAsync.value == null &&
            memoryAsync.isLoading &&
            !memoryAsync.hasValue &&
            !_running)) {
      return const SizedBox.shrink();
    }

    Widget body;
    if (artifactAsync.hasError && !artifactAsync.hasValue) {
      body = AgentResultPanelStateCard(
        icon: FLucideIcons.triangleAlert,
        title: l10n.commonError,
        message: userSafeErrorMessage(context, artifactAsync.error!),
        error: true,
        onRetry: _run,
      );
    } else {
      final artifact = artifactAsync.value;
      if (artifact != null) {
        body = _BriefingArtifactCard(
          artifact: artifact,
          running: _running,
          onRun: _run,
          onVisibilityChanged: () {
            ref.invalidate(
              health_agent_providers.latestMorningBriefingArtifactProvider,
            );
          },
        );
      } else if (memoryAsync.hasError && !memoryAsync.hasValue) {
        body = AgentResultPanelStateCard(
          icon: FLucideIcons.triangleAlert,
          title: l10n.commonError,
          message: userSafeErrorMessage(context, memoryAsync.error!),
          error: true,
          onRetry: _run,
        );
      } else {
        // Empty: compact generate CTA only — no large empty shell.
        final record = memoryAsync.value;
        body = record == null
            ? _BriefingEmpty(running: _running, onRun: _run)
            : _BriefingCard(record: record, running: _running, onRun: _run);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        body,
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            userSafeErrorMessage(context, _errorMessage!),
            style: context.captionStyle.copyWith(color: colors.destructive),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _BriefingArtifactCard extends StatelessWidget {
  const _BriefingArtifactCard({
    required this.artifact,
    required this.running,
    required this.onRun,
    required this.onVisibilityChanged,
  });

  final AgentArtifact artifact;
  final bool running;
  final VoidCallback onRun;
  final VoidCallback onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void openArtifact() {
      showAgentArtifactSheet(
        context: context,
        artifact: artifact,
        subtitle: l10n.healthBriefingUpdated(_ago(l10n, artifact.createdAt)),
        onVisibilityChanged: onVisibilityChanged,
      );
    }

    return AgentResultCard(
      artifact: artifact,
      metaLabel: l10n.healthBriefingUpdated(_ago(l10n, artifact.createdAt)),
      onOpen: openArtifact,
      summaryMaxLines: 8,
      footer: Align(
        alignment: Alignment.centerLeft,
        child: AppQuietButton(
          label: running
              ? l10n.healthBriefingGenerating
              : l10n.healthBriefingUpdate,
          onPress: running ? null : onRun,
          prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
          busy: running,
        ),
      ),
    );
  }
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({
    required this.record,
    required this.running,
    required this.onRun,
  });

  final MemoryRecord? record;
  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = record;
    if (r == null) return _BriefingEmpty(running: running, onRun: onRun);
    final outcome = r.payload['outcome'];
    final source = outcome is Map<String, Object?>
        ? outcome['synthesis_source']
        : null;
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final sourceLabel = source == 'llm' ? 'LLM' : l10n.healthBriefingAuto;
    return SoftCard(
      level: SoftCardLevel.raised,
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HealthPanelHeader(
            icon: FLucideIcons.sun,
            title: l10n.healthBriefingTitle,
            subtitle: l10n.healthBriefingUpdated(_ago(l10n, r.updatedAt)),
            color: colors.primary,
            trailing: source is String && source.isNotEmpty
                ? AppBadge(
                    label: sourceLabel,
                    size: AppBadgeSize.compact,
                    tone: source == 'llm'
                        ? AppBadgeTone.accent
                        : AppBadgeTone.neutral,
                  )
                : null,
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
                r.summary,
                style: typography.body.sm.copyWith(height: 1.45),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppQuietButton(
              label: running
                  ? l10n.healthBriefingGenerating
                  : l10n.healthBriefingUpdate,
              onPress: running ? null : onRun,
              prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
              busy: running,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact generate affordance — no marketing empty shell on Today.
class _BriefingEmpty extends StatelessWidget {
  const _BriefingEmpty({required this.running, required this.onRun});

  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      level: SoftCardLevel.flat,
      borderless: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: [
          Icon(
            FLucideIcons.sparkles,
            size: AppIconSizes.sm,
            color: context.theme.colors.primary,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Text(
              l10n.healthBriefingEmpty,
              style: context.bodyCaptionStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          AppQuietButton(
            label: running
                ? l10n.healthBriefingGenerating
                : l10n.healthBriefingGenerate,
            onPress: running ? null : onRun,
            busy: running,
          ),
        ],
      ),
    );
  }
}

