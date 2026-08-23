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
import '../agent_feedback_store.dart';
import '../agent_intents.dart';
import '../agent_run_store.dart';
import '../providers.dart' as agent_providers;

part 'agent_artifact_detail.dart';
part 'agent_artifact_detail_sections.dart';
part 'agent_result_stack.dart';

/// Domain-neutral presentation for user-visible agent output.
///
/// Prefer [AgentResultSurface] on domain homes — it keeps the artifact
/// readable and only overlays run status (running / failed).
enum AgentResultCardLayout {
  /// Full preview with insight excerpts; primary surface for domain homes.
  detailed,

  /// Calm feed summary: longer body text; whole card opens detail.
  summary,
}

class AgentResultCard extends StatelessWidget {
  const AgentResultCard({
    super.key,
    required this.artifact,
    required this.metaLabel,
    this.onOpen,
    this.footer,
    this.maxInsightPreviewCount = 2,
    this.summaryMaxLines,
    this.layout = AgentResultCardLayout.detailed,
  });

  final AgentArtifact artifact;
  final String metaLabel;
  final VoidCallback? onOpen;
  final Widget? footer;
  final int maxInsightPreviewCount;

  /// Override body line clamp. Defaults: detailed=6, summary=4.
  final int? summaryMaxLines;
  final AgentResultCardLayout layout;

  int get _resolvedSummaryLines =>
      summaryMaxLines ?? (layout == AgentResultCardLayout.summary ? 4 : 6);

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final accent = _accentColor(context, artifact.severity);
    final previewInsights = artifact.insights.take(maxInsightPreviewCount);
    final body = Text(
      artifact.summary,
      style: typography.body.sm.copyWith(height: 1.4),
      maxLines: _resolvedSummaryLines,
      overflow: TextOverflow.ellipsis,
    );

    if (layout == AgentResultCardLayout.summary) {
      return SoftCard(
        level: SoftCardLevel.raised,
        padding: AppPageRhythm.cardPadding,
        onPress: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AgentResultHeader(
              artifact: artifact,
              metaLabel: metaLabel,
              accent: accent,
              showChevron: onOpen != null,
            ),
            const SizedBox(height: AppSpacing.s10),
            body,
            if (footer != null) ...[
              const SizedBox(height: AppSpacing.s12),
              footer!,
            ],
          ],
        ),
      );
    }

    return SoftCard(
      level: SoftCardLevel.raised,
      padding: const EdgeInsets.all(AppSpacing.s16),
      // Whole card opens detail even when a secondary footer is present.
      onPress: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AgentResultHeader(
            artifact: artifact,
            metaLabel: metaLabel,
            accent: accent,
            showChevron: onOpen != null && footer != null,
          ),
          const SizedBox(height: AppSpacing.s12),
          body,
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

/// Result-first surface: artifact body stays visible; run state is an overlay.
///
/// - artifact + (optional) running/failed run → card + banner
/// - no artifact + run → [AgentRunStatusCard] only (first generation / failure)
class AgentResultSurface extends StatelessWidget {
  const AgentResultSurface({
    super.key,
    this.artifact,
    this.run,
    required this.metaLabel,
    this.onOpen,
    this.onRetry,
    this.footer,
    this.layout = AgentResultCardLayout.detailed,
    this.summaryMaxLines,
    this.maxInsightPreviewCount = 2,
  });

  final AgentArtifact? artifact;
  final AgentRunRecord? run;
  final String metaLabel;
  final VoidCallback? onOpen;
  final FutureOr<void> Function()? onRetry;
  final Widget? footer;
  final AgentResultCardLayout layout;
  final int? summaryMaxLines;
  final int maxInsightPreviewCount;

  @override
  Widget build(BuildContext context) {
    final art = artifact;
    final activeRun = run;
    final overlay =
        activeRun != null &&
            agent_providers.AgentResultBundle.shouldPrioritizeRun(
              activeRun,
              art,
            )
        ? activeRun
        : null;

    if (art != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (overlay != null) ...[
            _RunStatusBanner(record: overlay, onRetry: onRetry),
            const SizedBox(height: AppSpacing.s8),
          ],
          AgentResultCard(
            artifact: art,
            metaLabel: metaLabel,
            onOpen: onOpen,
            footer: footer,
            layout: layout,
            summaryMaxLines: summaryMaxLines,
            maxInsightPreviewCount: maxInsightPreviewCount,
          ),
        ],
      );
    }

    if (activeRun != null) {
      return AgentRunStatusCard(
        record: activeRun,
        metaLabel: metaLabel,
        onRetry: onRetry,
      );
    }

    return const SizedBox.shrink();
  }
}

typedef AgentResultMetaLabelBuilder = String Function(DateTime at);
typedef AgentResultOpenCallback = void Function(AgentArtifact artifact);
typedef AgentResultRetryCallback = FutureOr<void> Function(String agentId);

/// Canonical multi-agent result composition for domain surfaces.
///
/// The highest-priority result starts at the front. When multiple agents have
/// visible results, users swipe the front card horizontally to cycle through
/// one full result at a time. Pairing, severity ordering, and run overlays come
/// from [agent_providers.AgentResultBundle] rather than each domain page.
class AgentResultsSection extends StatelessWidget {
  const AgentResultsSection({
    super.key,
    required this.bundle,
    required this.metaLabelBuilder,
    required this.onOpen,
    this.onRetry,
    this.maxResults = 5,
    this.summaryMaxLines,
  });

  final agent_providers.AgentResultBundle bundle;
  final AgentResultMetaLabelBuilder metaLabelBuilder;
  final AgentResultOpenCallback onOpen;
  final AgentResultRetryCallback? onRetry;
  final int maxResults;
  final int? summaryMaxLines;

  @override
  Widget build(BuildContext context) {
    final entries = bundle.visibleEntries
        .take(maxResults)
        .toList(growable: false);
    if (entries.isEmpty) return const SizedBox.shrink();
    Widget buildEntry(agent_providers.AgentResultEntry entry) {
      final artifact = entry.artifact;
      final run = entry.runOverlay;
      return AgentResultSurface(
        artifact: artifact,
        run: run,
        metaLabel: metaLabelBuilder(artifact?.createdAt ?? entry.referenceTime),
        layout: AgentResultCardLayout.summary,
        summaryMaxLines: summaryMaxLines,
        onOpen: artifact == null ? null : () => onOpen(artifact),
        onRetry: run == null || onRetry == null
            ? null
            : () => onRetry!(entry.agentId),
      );
    }

    if (entries.length == 1) return buildEntry(entries.first);

    return _SwipeableAgentResultStack(
      entries: entries,
      entryBuilder: buildEntry,
    );
  }
}

/// Slim banner so running/failed does not replace the previous result body.
class _RunStatusBanner extends StatefulWidget {
  const _RunStatusBanner({required this.record, this.onRetry});

  final AgentRunRecord record;
  final FutureOr<void> Function()? onRetry;

  @override
  State<_RunStatusBanner> createState() => _RunStatusBannerState();
}

class _RunStatusBannerState extends State<_RunStatusBanner> {
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
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final record = widget.record;
    final failed = record.status == AgentRunLifecycleStatus.failed;
    final running = record.status == AgentRunLifecycleStatus.running;
    final accent = failed ? context.appTheme.status.danger.fg : colors.primary;
    final message = failed
        ? (record.error ?? record.summary ?? l10n.agentResultRetryAction)
        : (record.summary ?? l10n.agentResultLoadingBody);

    return SoftCard(
      level: SoftCardLevel.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      child: Row(
        children: [
          if (running)
            const SizedBox(
              width: AppIconSizes.sm,
              height: AppIconSizes.sm,
              child: FCircularProgress(),
            )
          else
            Icon(
              failed ? FLucideIcons.triangleAlert : FLucideIcons.info,
              size: AppIconSizes.sm,
              color: accent,
            ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Text(
              message,
              style: context.captionStyle.copyWith(color: accent),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (failed && widget.onRetry != null) ...[
            const SizedBox(width: AppSpacing.s8),
            AppQuietButton(
              label: l10n.agentResultRetryAction,
              onPress: _retrying ? null : _retry,
              busy: _retrying,
              prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.xs),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentResultHeader extends StatelessWidget {
  const _AgentResultHeader({
    required this.artifact,
    required this.metaLabel,
    required this.accent,
    this.showChevron = false,
  });

  final AgentArtifact artifact;
  final String metaLabel;
  final Color accent;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
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
        if (showChevron) ...[
          const SizedBox(width: AppSpacing.s6),
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.xs,
            color: context.theme.colors.mutedForeground,
          ),
        ],
      ],
    );
  }
}

class AgentCompactResultRow extends StatelessWidget {
  const AgentCompactResultRow({
    super.key,
    required this.artifact,
    required this.metaLabel,
    this.run,
    this.onOpen,
  });

  final AgentArtifact artifact;
  final String metaLabel;
  final AgentRunRecord? run;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = _accentColor(context, artifact.severity);
    final liveRun =
        run != null &&
            agent_providers.AgentResultBundle.shouldPrioritizeRun(
              run!,
              artifact,
            )
        ? run
        : null;
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
            label: liveRun == null
                ? _badgeLabel(l10n, artifact)
                : _statusLabel(l10n, liveRun.status),
            size: AppBadgeSize.compact,
            tone: liveRun == null
                ? _badgeTone(artifact.severity)
                : _badgeToneForRun(liveRun.status),
            icon: liveRun == null ? null : _iconForRunStatus(liveRun.status),
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
    final l10n = AppLocalizations.of(context);
    final accent = error ? context.appTheme.status.danger.fg : colors.primary;
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
