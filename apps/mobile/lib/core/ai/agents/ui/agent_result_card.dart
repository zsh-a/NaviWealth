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
        borderless: true,
        padding: const EdgeInsets.all(AppSpacing.s14),
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
      borderless: true,
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

typedef _AgentResultEntryBuilder =
    Widget Function(agent_providers.AgentResultEntry entry);

class _SwipeableAgentResultStack extends StatefulWidget {
  const _SwipeableAgentResultStack({
    required this.entries,
    required this.entryBuilder,
  });

  final List<agent_providers.AgentResultEntry> entries;
  final _AgentResultEntryBuilder entryBuilder;

  @override
  State<_SwipeableAgentResultStack> createState() =>
      _SwipeableAgentResultStackState();
}

class _SwipeableAgentResultStackState extends State<_SwipeableAgentResultStack>
    with SingleTickerProviderStateMixin {
  static const double _switchThreshold = 48;
  static const double _velocityThreshold = 450;
  static const double _maxDragOffset = 96;

  late String _activeAgentId = widget.entries.first.agentId;
  late final AnimationController _motionController;
  double _dragOffset = 0;
  bool _settling = false;

  int get _activeIndex {
    final index = widget.entries.indexWhere(
      (entry) => entry.agentId == _activeAgentId,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController.unbounded(vsync: this)
      ..addListener(_handleMotionTick);
  }

  void _handleMotionTick() {
    if (!mounted) return;
    setState(() => _dragOffset = _motionController.value);
  }

  @override
  void dispose() {
    _motionController
      ..removeListener(_handleMotionTick)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SwipeableAgentResultStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final leadingChanged =
        oldWidget.entries.first.agentId != widget.entries.first.agentId;
    final activeStillExists = widget.entries.any(
      (entry) => entry.agentId == _activeAgentId,
    );
    if (leadingChanged || !activeStillExists) {
      _motionController.stop();
      _activeAgentId = widget.entries.first.agentId;
      _dragOffset = 0;
      _motionController.value = 0;
      _settling = false;
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (_settling) return;
    _motionController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_settling) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx)
          .clamp(-_maxDragOffset, _maxDragOffset)
          .toDouble();
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_settling) return;
    final velocity = details.primaryVelocity ?? 0;
    final shouldSwitch =
        _dragOffset.abs() >= _switchThreshold ||
        velocity.abs() >= _velocityThreshold;
    if (!shouldSwitch) {
      unawaited(_animateBack());
      return;
    }
    final direction = _dragOffset != 0 ? _dragOffset.sign : velocity.sign;
    unawaited(
      _switchCard(step: direction < 0 ? 1 : -1, exitDirection: direction),
    );
  }

  void _onDragCancel() {
    if (_settling) return;
    unawaited(_animateBack());
  }

  Future<void> _animateBack() async {
    setState(() => _settling = true);
    final duration = AppMotionPolicy.duration(context, Motion.medium);
    final completed = await _animateOffset(
      0,
      duration: duration,
      curve: Motion.standardDecelerate,
    );
    if (mounted && completed) setState(() => _settling = false);
  }

  Future<void> _switchCard({
    required int step,
    required double exitDirection,
  }) async {
    setState(() => _settling = true);
    final renderBox = context.findRenderObject();
    final measuredWidth = renderBox is RenderBox ? renderBox.size.width : 0.0;
    final fallbackWidth = MediaQuery.sizeOf(context).width;
    final deckWidth = measuredWidth > 0 ? measuredWidth : fallbackWidth;
    final exitTarget = exitDirection * deckWidth * 0.92;
    final exited = await _animateOffset(
      exitTarget,
      duration: AppMotionPolicy.duration(context, Motion.fast),
      curve: Motion.standardAccelerate,
    );
    if (!mounted || !exited) return;

    final nextIndex = (_activeIndex + step) % widget.entries.length;
    final incomingOffset = -exitDirection * AppSpacing.s48;
    setState(() {
      _activeAgentId = widget.entries[nextIndex].agentId;
      _dragOffset = incomingOffset;
    });
    _motionController.value = incomingOffset;
    final entered = await _animateOffset(
      0,
      duration: AppMotionPolicy.duration(context, Motion.medium),
      curve: Motion.standardDecelerate,
    );
    if (mounted && entered) setState(() => _settling = false);
  }

  Future<bool> _animateOffset(
    double target, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (duration == Duration.zero) {
      _motionController.value = target;
      return true;
    }
    _motionController.value = _dragOffset;
    try {
      await _motionController
          .animateTo(target, duration: duration, curve: curve)
          .orCancel;
      return true;
    } on TickerCanceled {
      // A new data snapshot or disposal superseded this motion.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.entries[_activeIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final revealProgress = (_dragOffset.abs() / _maxDragOffset)
            .clamp(0.0, 1.0)
            .toDouble();
        final exitProgress = (_dragOffset.abs() / (width * 0.92))
            .clamp(0.0, 1.0)
            .toDouble();
        final rotation = width == 0 ? 0.0 : (_dragOffset / width) * 0.035;
        final opacity = (1 - exitProgress * exitProgress)
            .clamp(0.0, 1.0)
            .toDouble();
        double lerp(double from, double to) =>
            from + (to - from) * revealProgress;

        return Stack(
          key: const ValueKey<String>('agent-result-stack'),
          children: [
            Positioned.fill(
              left: lerp(AppSpacing.s12, AppSpacing.s6),
              right: lerp(AppSpacing.s12, AppSpacing.s6),
              top: lerp(AppSpacing.s16, AppSpacing.s8),
              bottom: lerp(0, AppSpacing.s8),
              child: const _AgentResultBackplate(level: 2),
            ),
            Positioned.fill(
              left: lerp(AppSpacing.s6, 0),
              right: lerp(AppSpacing.s6, 0),
              top: lerp(AppSpacing.s8, 0),
              bottom: lerp(AppSpacing.s8, AppSpacing.s16),
              child: const _AgentResultBackplate(level: 1),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s16),
              child: GestureDetector(
                key: const ValueKey<String>('agent-result-front-card'),
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                child: Opacity(
                  opacity: opacity,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.translationValues(_dragOffset, 0, 0)
                      ..rotateZ(rotation),
                    child: KeyedSubtree(
                      key: ValueKey<String>(active.agentId),
                      child: widget.entryBuilder(active),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.s4,
              child: _AgentResultPageIndicator(
                count: widget.entries.length,
                activeIndex: _activeIndex,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AgentResultBackplate extends StatelessWidget {
  const _AgentResultBackplate({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colors.muted.withValues(
              alpha: level == 1 ? AppOpacity.subtle : AppOpacity.faint,
            ),
            colors.card,
          ),
          border: Border.all(
            color: colors.border.withValues(alpha: AppOpacity.highlight),
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}

class _AgentResultPageIndicator extends StatelessWidget {
  const _AgentResultPageIndicator({
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final duration = AppMotionPolicy.duration(context, Motion.fast);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++) ...[
          AnimatedContainer(
            duration: duration,
            curve: Motion.standardDecelerate,
            width: index == activeIndex ? AppSpacing.s12 : AppSpacing.s4,
            height: AppSpacing.s4,
            decoration: BoxDecoration(
              color: index == activeIndex ? colors.primary : colors.border,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          if (index != count - 1) const SizedBox(width: AppSpacing.s4),
        ],
      ],
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
    final accent = failed ? SemanticColors.of(context).danger : colors.primary;
    final message = failed
        ? (record.error ?? record.summary ?? l10n.agentResultRetryAction)
        : (record.summary ?? l10n.agentResultLoadingBody);

    return SoftCard(
      level: SoftCardLevel.flat,
      borderless: true,
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
              style: context.captionStyle.copyWith(
                color: colors.mutedForeground,
                fontSize: 10,
              ),
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

class _EvidenceMethodAccordion extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                for (final ref in evidence) ...[
                  _DetailTile(
                    icon: FLucideIcons.fileText,
                    title: ref.label ?? l10n.agentResultEvidenceSection,
                    body:
                        ref.description ??
                        l10n.agentResultEvidenceAvailableBody,
                    color: color,
                    trailingIcon: ref.route == null
                        ? null
                        : FLucideIcons.externalLink,
                    onPress: ref.route == null
                        ? null
                        : () => _openArtifactRoute(context, ref.route!),
                  ),
                  if (ref.details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s40,
                        0,
                        AppSpacing.s4,
                        AppSpacing.s8,
                      ),
                      child: _MetricDetails(metrics: ref.details),
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
      child: FTappable(onPress: onPress, child: content),
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
