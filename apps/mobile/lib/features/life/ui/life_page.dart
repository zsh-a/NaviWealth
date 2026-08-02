/// Cross-domain Life hub — brief signals, not a third activity feed.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/core/shell/domain_switcher.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/life/data/life_events_provider.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';
import 'package:naviwealth/features/life/ui/life_event_l10n.dart';
import 'package:naviwealth/features/life/ui/life_signal_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Recent, non-priority rows visible before the timeline is expanded.
const int _kRecentCollapsedCap = 4;

class LifePage extends ConsumerWidget {
  const LifePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final packs = ref.watch(lifeWorkbenchDomainsProvider);
    final events = ref.watch(lifeEventsProvider);
    final hero = ref.watch(lifeHeroSummaryProvider);
    final reviewPacks = packs
        .where((pack) => pack.reviewRoutePath != null)
        .toList(growable: false);
    final formatters = context.formatters(ref);
    final priorityEvents = events
        .where((event) => event.priority == LifeSignalPriority.high)
        .toList(growable: false);
    final recentEvents = events
        .where((event) => event.priority != LifeSignalPriority.high)
        .toList(growable: false);
    final eventPresentation = _LifeEventPresentation(
      executionEnabled: packs.any(
        (pack) => pack.scope == DomainScope.execution,
      ),
      l10n: l10n,
      timeLabel: (at) => formatters.time(at),
      iconFor: _iconFor,
      accentFor: (event) => _accentFor(context, event),
      domainLabel: (scope) => _domainLabel(l10n, scope),
    );
    return ShellCanvasScaffold(
      childPad: false,
      child: SafeArea(
        bottom: false,
        child: BriefScaffold(
          // The Life hub is the initial route: it must be refreshable and
          // width-capped like every domain Today surface (doc 15 §7.3).
          onRefresh: () async {
            final sync = await ref.read(syncSchedulerProvider.future);
            await sync?.triggerNow();
            ref.invalidate(lifeSignalSnapshotProvider);
            ref.invalidate(lifeEventsProvider);
            ref.invalidate(lifeHeroSummaryProvider);
          },
          maxContentWidth: AdaptiveMaxWidth.page,
          greeting: _LifeGreeting(l10n: l10n),
          stage: AppCollapsingStage(
            child: _LifeHero(l10n: l10n, summary: hero),
          ),
          stickyBuilder: (context, progress) => AppCollapsedSummaryBar(
            progress: progress,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hero.localizedMetricLabel(l10n),
                    style: context.mutedLabelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  hero.localizedSticky(l10n),
                  style: TypographyTokens.numericTitleStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          summaryTiles: [
            if (priorityEvents.isNotEmpty)
              AdaptiveSummaryTile(
                span: AdaptiveSummaryTileSpan.featured,
                child: _LifeEventSection(
                  title: l10n.lifeTimelinePriorityTitle,
                  events: priorityEvents,
                  presentation: eventPresentation,
                ),
              ),
            if (reviewPacks.isNotEmpty)
              AdaptiveSummaryTile(
                child: _LifeReviewEntry(packs: reviewPacks, l10n: l10n),
              ),
            if (recentEvents.isNotEmpty)
              AdaptiveSummaryTile(
                span: priorityEvents.isNotEmpty
                    ? AdaptiveSummaryTileSpan.full
                    : AdaptiveSummaryTileSpan.featured,
                child: _LifeEventSection(
                  title: l10n.lifeTimelineTitle,
                  events: recentEvents,
                  presentation: eventPresentation,
                  collapsedCap: _kRecentCollapsedCap,
                ),
              )
            else if (priorityEvents.isEmpty)
              AdaptiveSummaryTile(child: _LifeEmptySection(l10n: l10n)),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(LifeEvent e) => switch (e.template) {
    LifeEventTemplate.financeDaySummary => FLucideIcons.receipt,
    LifeEventTemplate.financeBudgetPressure => FLucideIcons.gauge,
    LifeEventTemplate.recoveryAlert => FLucideIcons.heartPulse,
    LifeEventTemplate.executionBlocked => FLucideIcons.octagonAlert,
    LifeEventTemplate.executionDue => FLucideIcons.calendarClock,
    LifeEventTemplate.knowledgeInbox => FLucideIcons.inbox,
    LifeEventTemplate.agentResult => FLucideIcons.sparkles,
  };

  static Color _accentFor(BuildContext context, LifeEvent e) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    if (e.priority == LifeSignalPriority.high) {
      return switch (e.domain) {
        DomainScope.health => colors.destructive,
        DomainScope.execution => status.warning.fg,
        _ => colors.primary,
      };
    }
    return switch (e.domain) {
      DomainScope.finance => colors.primary,
      DomainScope.health => status.success.fg,
      DomainScope.knowledge => status.info.fg,
      DomainScope.execution => status.warning.fg,
    };
  }

  static String _domainLabel(AppLocalizations l10n, DomainScope scope) =>
      switch (scope) {
        DomainScope.finance => l10n.lifeDomainFinance,
        DomainScope.health => l10n.lifeDomainHealth,
        DomainScope.knowledge => l10n.lifeDomainKnowledge,
        DomainScope.execution => l10n.lifeDomainExecution,
      };
}

class _LifeReviewEntry extends StatelessWidget {
  const _LifeReviewEntry({required this.packs, required this.l10n});

  final List<DomainPack> packs;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.module(title: l10n.lifeReviewTitle),
        SoftCard.raised(
          key: const ValueKey<String>('life-review-entry'),
          padding: AppPageRhythm.densePadding,
          onPress: () => _open(context),
          child: Row(
            children: [
              AppIconTile(
                icon: FLucideIcons.clipboardCheck,
                color: context.theme.colors.primary,
                size: 32,
                iconSize: AppIconSizes.sm,
                radius: AppRadius.sm,
                backgroundOpacity: AppOpacity.subtle,
                foregroundOpacity: 1,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.lifeReviewHeadline, style: context.rowTitleStyle),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      l10n.lifeReviewSubtitle,
                      style: context.captionStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.sm,
                color: context.theme.colors.mutedForeground,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    if (packs.length == 1) {
      context.go(packs.single.reviewRoutePath!);
      return;
    }
    await showAppSheet<void>(
      context: context,
      title: l10n.lifeReviewTitle,
      subtitle: l10n.lifeReviewPickerSubtitle,
      builder: (sheetContext) => AppActionSheetList(
        children: [
          for (final pack in packs)
            AppActionSheetTile(
              icon: pack.scope == DomainScope.knowledge
                  ? FLucideIcons.brain
                  : FLucideIcons.listChecks,
              title: LifePage._domainLabel(l10n, pack.scope),
              onPress: () {
                Navigator.of(sheetContext).pop();
                context.go(pack.reviewRoutePath!);
              },
            ),
        ],
      ),
    );
  }
}

class _LifeGreeting extends StatelessWidget {
  const _LifeGreeting({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? l10n.homeGreetingNight
        : hour < 12
        ? l10n.homeGreetingMorning
        : hour < 18
        ? l10n.homeGreetingAfternoon
        : l10n.homeGreetingEvening;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  greeting,
                  style: context.displayTitleStyle.copyWith(height: 1.05),
                ),
              ),
              const ShellActionRow(),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(l10n.lifeBriefSubtitle, style: context.captionStyle),
        ],
      ),
    );
  }
}

/// Compact cross-domain status. The actionable rows below own the visual
/// hierarchy; this stage only establishes context and must not push them below
/// the fold.
class _LifeHero extends StatelessWidget {
  const _LifeHero({required this.l10n, required this.summary});

  final AppLocalizations l10n;
  final LifeHeroSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    final metricColor = summary.hasAttention
        ? status.warning.fg
        : summary.isCalm
        ? colors.mutedForeground
        : colors.primary;

    return SoftCard.raised(
      key: const ValueKey('life-summary-card'),
      padding: AppPageRhythm.densePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppIconTile(
            icon: FLucideIcons.sparkles,
            color: metricColor,
            size: 32,
            iconSize: AppIconSizes.sm,
            radius: AppRadius.sm,
            backgroundOpacity: AppOpacity.subtle,
            foregroundOpacity: 1,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary.localizedHeadline(l10n),
                  style: context.rowTitleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  summary.localizedBody(l10n),
                  style: context.captionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!summary.isCalm) ...[
            const SizedBox(width: AppSpacing.s12),
            AppBadge(
              label:
                  '${summary.primaryMetric} ${summary.localizedMetricLabel(l10n)}',
              tone: summary.hasAttention
                  ? AppBadgeTone.warning
                  : AppBadgeTone.accent,
              size: AppBadgeSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _LifeEventPresentation {
  const _LifeEventPresentation({
    required this.executionEnabled,
    required this.l10n,
    required this.timeLabel,
    required this.iconFor,
    required this.accentFor,
    required this.domainLabel,
  });

  final bool executionEnabled;
  final AppLocalizations l10n;
  final String Function(DateTime at) timeLabel;
  final IconData Function(LifeEvent e) iconFor;
  final Color Function(LifeEvent e) accentFor;
  final String Function(DomainScope scope) domainLabel;
}

/// One semantic tier of the life stream. Priority and recent events share the
/// same presentation contract, while only the recent tier is collapsible.
class _LifeEventSection extends StatefulWidget {
  const _LifeEventSection({
    required this.title,
    required this.events,
    required this.presentation,
    this.collapsedCap,
  });

  final String title;
  final List<LifeEvent> events;
  final _LifeEventPresentation presentation;
  final int? collapsedCap;

  @override
  State<_LifeEventSection> createState() => _LifeEventSectionState();
}

class _LifeEventSectionState extends State<_LifeEventSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    final cap = widget.collapsedCap;
    final shown = cap == null || _expanded
        ? events
        : events.take(cap).toList(growable: false);
    final hiddenCount = events.length - shown.length;
    final showToggle = cap != null && events.length > cap;
    final presentation = widget.presentation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.module(title: widget.title),
        LifeTimeline(
          items: [
            for (final event in shown)
              LifeTimelineItem(
                id: event.id,
                at: event.at,
                title: event.localizedTitle(presentation.l10n),
                subtitle: event.localizedSubtitle(presentation.l10n),
                icon: presentation.iconFor(event),
                accent: presentation.accentFor(event),
                domainLabel: presentation.domainLabel(event.domain),
                onOpen: _onOpen(context, event),
                onAction: _onAction(context, event),
                actionLabel: _actionLabel(event),
              ),
          ],
          timeLabel: presentation.timeLabel,
        ),
        if (showToggle) ...[
          const SizedBox(height: AppPageRhythm.row),
          AppRevealControl(
            expanded: _expanded,
            collapsedLabel: presentation.l10n.lifeTimelineShowMore(hiddenCount),
            expandedLabel: presentation.l10n.lifeTimelineShowLess,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
        ],
      ],
    );
  }

  VoidCallback? _onOpen(BuildContext context, LifeEvent event) {
    final path = event.routePath;
    return path == null ? null : () => context.go(path);
  }

  VoidCallback? _onAction(BuildContext context, LifeEvent event) {
    if (event.actionSuggestion == null) return null;
    return () async {
      await showLifeSignalSheet(
        context: context,
        event: event,
        executionEnabled: widget.presentation.executionEnabled,
      );
    };
  }

  String? _actionLabel(LifeEvent event) {
    if (event.actionSuggestion == null) return null;
    final l10n = widget.presentation.l10n;
    return l10n.lifeSignalCreateActionFor(event.localizedTitle(l10n));
  }
}

class _LifeEmptySection extends StatelessWidget {
  const _LifeEmptySection({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SoftCard.raised(
      padding: AppPageRhythm.cardPadding,
      child: Consumer(
        builder: (context, ref, _) => AppEmptyState(
          icon: FLucideIcons.sparkles,
          title: l10n.lifeTimelineEmptyTitle,
          message: l10n.lifeTimelineEmpty,
          compact: true,
          iconSize: AppIconSizes.lg,
          action: FButton(
            variant: FButtonVariant.outline,
            onPress: () => showDomainSwitcherSheet(
              context,
              ref.read(activeDomainShellsProvider),
              ref.read<String?>(domainSwitcherHomePathProvider),
            ),
            child: Text(l10n.shellSwitchDomainTitle),
          ),
        ),
      ),
    );
  }
}
