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
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
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
    final primaryModules = <Widget>[
      if (priorityEvents.isNotEmpty)
        _LifeEventSection(
          title: l10n.lifeTimelinePriorityTitle,
          events: priorityEvents,
          presentation: eventPresentation,
        ),
      if (packs.isNotEmpty)
        _WorkspaceGrid(packs: packs, l10n: l10n, summary: hero),
    ];

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
          modules: [
            if (primaryModules.isNotEmpty) _LifePrimaryModules(primaryModules),
          ],
          secondary: [
            if (recentEvents.isNotEmpty)
              _LifeEventSection(
                title: l10n.lifeTimelineTitle,
                events: recentEvents,
                presentation: eventPresentation,
                collapsedCap: _kRecentCollapsedCap,
              )
            else if (priorityEvents.isEmpty)
              _LifeEmptySection(l10n: l10n),
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

/// Equal-width domain destinations. Intrinsic-width chips caused the two rows
/// to drift whenever a label or signal badge changed; the grid keeps a stable
/// scan line across locales and viewport sizes.
class _WorkspaceGrid extends StatelessWidget {
  const _WorkspaceGrid({
    required this.packs,
    required this.l10n,
    required this.summary,
  });

  final List<DomainPack> packs;
  final AppLocalizations l10n;
  final LifeHeroSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.module(title: l10n.lifeWorkbenchTitle),
        LayoutBuilder(
          builder: (context, constraints) {
            final desiredColumns =
                constraints.maxWidth >= Breakpoints.contentThreeColumn ? 4 : 2;
            final columns = packs.length < desiredColumns
                ? packs.length
                : desiredColumns;
            final tileWidth =
                (constraints.maxWidth - AppPageRhythm.row * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppPageRhythm.row,
              runSpacing: AppPageRhythm.row,
              children: [
                for (final pack in packs)
                  SizedBox(
                    key: ValueKey('life-domain-${pack.scope.wire}'),
                    width: tileWidth,
                    child: _DomainTile(
                      pack: pack,
                      l10n: l10n,
                      colors: colors,
                      status: status,
                      signalCount: summary.signalsFor(pack.scope),
                      highCount: summary.highFor(pack.scope),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DomainTile extends StatelessWidget {
  const _DomainTile({
    required this.pack,
    required this.l10n,
    required this.colors,
    required this.status,
    required this.signalCount,
    required this.highCount,
  });

  final DomainPack pack;
  final AppLocalizations l10n;
  final FColors colors;
  final AppStatus status;
  final int signalCount;
  final int highCount;

  @override
  Widget build(BuildContext context) {
    final path = pack.tabPaths.isNotEmpty
        ? pack.tabPaths.first
        : FinanceRoutes.home;
    final spec = pack.shellSpecBuilder?.call(l10n);
    final label = spec?.label ?? pack.scope.wire;
    final icon = spec?.icon ?? FLucideIcons.layers;
    final accent = highCount > 0
        ? switch (pack.scope) {
            DomainScope.health => colors.destructive,
            DomainScope.execution => status.warning.fg,
            DomainScope.knowledge => status.info.fg,
            DomainScope.finance => colors.primary,
          }
        : colors.primary;

    return SoftCard.raised(
      padding: AppPageRhythm.densePadding,
      onPress: () => context.go(path),
      child: Row(
        children: [
          AppIconTile(
            icon: icon,
            color: accent,
            size: 28,
            iconSize: AppIconSizes.sm,
            radius: AppRadius.sm,
            backgroundOpacity: AppOpacity.subtle,
            foregroundOpacity: 1,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              label,
              style: context.labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (signalCount > 0) ...[
            const SizedBox(width: AppSpacing.s8),
            AppBadge(
              label: '$signalCount',
              size: AppBadgeSize.compact,
              tone: highCount > 0 ? AppBadgeTone.warning : AppBadgeTone.accent,
              minWidth: 22,
            ),
          ],
        ],
      ),
    );
  }
}

/// Keeps the action surface and workspace navigation in one responsive module.
/// Narrow screens preserve task-first reading order; wide canvases use two
/// balanced columns without changing the semantic order.
class _LifePrimaryModules extends StatelessWidget {
  const _LifePrimaryModules(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.length == 1) return children.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.contentTwoColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppPageRhythm.section),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children.first),
            const SizedBox(width: AppPageRhythm.section),
            Expanded(child: children.last),
          ],
        );
      },
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
