/// Cross-domain Life hub — brief signals, not a third activity feed.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/life/data/life_events_provider.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';
import 'package:naviwealth/features/life/ui/life_event_l10n.dart';
import 'package:naviwealth/features/life/ui/life_signal_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Max attention rows when the list is collapsed.
const int _kAttentionCollapsedCap = 5;

class LifePage extends ConsumerWidget {
  const LifePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final packs = ref.watch(lifeWorkbenchDomainsProvider);
    final events = ref.watch(lifeEventsProvider);
    final hero = ref.watch(lifeHeroSummaryProvider);
    final formatters = context.formatters(ref);

    return ShellCanvasScaffold(
      childPad: false,
      child: SafeArea(
        bottom: false,
        child: BriefScaffold(
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
            if (packs.isNotEmpty)
              _WorkspaceChips(packs: packs, l10n: l10n, summary: hero),
          ],
          secondary: [
            _AttentionSection(
              events: events,
              executionEnabled: packs.any(
                (pack) => pack.scope == DomainScope.execution,
              ),
              l10n: l10n,
              timeLabel: (at) => formatters.time(at),
              iconFor: _iconFor,
              accentFor: (e) => _accentFor(context, e),
              domainLabel: (scope) => _domainLabel(l10n, scope),
            ),
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
    final semantic = SemanticColors.of(context);
    if (e.priority == LifeSignalPriority.high) {
      return switch (e.domain) {
        DomainScope.health => colors.destructive,
        DomainScope.execution => semantic.warning,
        _ => colors.primary,
      };
    }
    return switch (e.domain) {
      DomainScope.finance => colors.primary,
      DomainScope.health => semantic.success,
      DomainScope.knowledge => semantic.info,
      DomainScope.execution => semantic.warning,
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

/// Stage: conclusion copy + primary metric number (Health/Execution pattern).
class _LifeHero extends StatelessWidget {
  const _LifeHero({required this.l10n, required this.summary});

  final AppLocalizations l10n;
  final LifeHeroSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    final metricColor = summary.hasAttention
        ? semantic.warning
        : summary.isCalm
        ? colors.mutedForeground
        : colors.primary;

    return SoftCard.hero(
      padding: AppPageRhythm.heroPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.localizedMetricLabel(l10n),
                  style: context.mutedLabelStyle,
                ),
                const SizedBox(height: AppPageRhythm.row),
                Text(
                  summary.localizedHeadline(l10n),
                  style: TypographyTokens.displaySmall.copyWith(height: 1.15),
                ),
                const SizedBox(height: AppPageRhythm.row),
                Text(
                  summary.localizedBody(l10n),
                  style: context.bodyCaptionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            '${summary.primaryMetric}',
            style: TypographyTokens.displayLarge.copyWith(
              color: metricColor,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal domain chips with per-domain signal badges.
class _WorkspaceChips extends StatelessWidget {
  const _WorkspaceChips({
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
    final semantic = SemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.lifeWorkbenchTitle,
          padding: const EdgeInsets.only(
            left: AppSpacing.s4,
            bottom: AppPageRhythm.row,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < packs.length; i++) ...[
                if (i > 0) const SizedBox(width: AppPageRhythm.row),
                _DomainChip(
                  pack: packs[i],
                  l10n: l10n,
                  colors: colors,
                  semantic: semantic,
                  signalCount: summary.signalsFor(packs[i].scope),
                  highCount: summary.highFor(packs[i].scope),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DomainChip extends StatelessWidget {
  const _DomainChip({
    required this.pack,
    required this.l10n,
    required this.colors,
    required this.semantic,
    required this.signalCount,
    required this.highCount,
  });

  final DomainPack pack;
  final AppLocalizations l10n;
  final FColors colors;
  final SemanticColors semantic;
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
            DomainScope.execution => semantic.warning,
            DomainScope.knowledge => semantic.info,
            DomainScope.finance => colors.primary,
          }
        : colors.primary;

    return SoftCard.raised(
      borderless: true,
      padding: AppPageRhythm.densePadding,
      onPress: () => context.go(path),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
          Text(label, style: context.labelStyle),
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

/// Attention stream: high-priority first, then the rest, with expand/collapse.
class _AttentionSection extends StatefulWidget {
  const _AttentionSection({
    required this.events,
    required this.executionEnabled,
    required this.l10n,
    required this.timeLabel,
    required this.iconFor,
    required this.accentFor,
    required this.domainLabel,
  });

  final List<LifeEvent> events;
  final bool executionEnabled;
  final AppLocalizations l10n;
  final String Function(DateTime at) timeLabel;
  final IconData Function(LifeEvent e) iconFor;
  final Color Function(LifeEvent e) accentFor;
  final String Function(DomainScope scope) domainLabel;

  @override
  State<_AttentionSection> createState() => _AttentionSectionState();
}

class _AttentionSectionState extends State<_AttentionSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    final l10n = widget.l10n;

    if (events.isEmpty) {
      return SoftCard.raised(
        padding: AppPageRhythm.cardPadding,
        borderless: true,
        child: AppEmptyState(
          icon: FLucideIcons.sparkles,
          title: l10n.lifeTimelineEmptyTitle,
          message: l10n.lifeTimelineEmpty,
          compact: true,
          iconSize: AppIconSizes.lg,
        ),
      );
    }

    final high = events
        .where((e) => e.priority == LifeSignalPriority.high)
        .toList(growable: false);
    final normal = events
        .where((e) => e.priority != LifeSignalPriority.high)
        .toList(growable: false);

    // High-priority is never truncated. Cap only applies to the normal tier.
    final shownHigh = high;
    final List<LifeEvent> shownNormal;
    if (_expanded) {
      shownNormal = normal;
    } else {
      final remaining = (_kAttentionCollapsedCap - high.length).clamp(
        0,
        normal.length,
      );
      shownNormal = remaining == 0
          ? const <LifeEvent>[]
          : normal.take(remaining).toList(growable: false);
    }
    final hiddenCount = events.length - shownHigh.length - shownNormal.length;
    final showToggle = events.length > _kAttentionCollapsedCap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shownHigh.isNotEmpty) ...[
          SectionHeader(
            title: l10n.lifeTimelinePriorityTitle,
            padding: const EdgeInsets.only(
              left: AppSpacing.s4,
              bottom: AppPageRhythm.row,
            ),
          ),
          LifeTimeline(
            items: [
              for (final e in shownHigh)
                LifeTimelineItem(
                  id: e.id,
                  at: e.at,
                  title: e.localizedTitle(l10n),
                  subtitle: e.localizedSubtitle(l10n),
                  icon: widget.iconFor(e),
                  accent: widget.accentFor(e),
                  domainLabel: widget.domainLabel(e.domain),
                  onOpen: _onOpen(context, e),
                ),
            ],
            timeLabel: widget.timeLabel,
          ),
          if (shownNormal.isNotEmpty)
            const SizedBox(height: AppPageRhythm.section),
        ],
        if (shownNormal.isNotEmpty) ...[
          SectionHeader(
            title: l10n.lifeTimelineTitle,
            padding: const EdgeInsets.only(
              left: AppSpacing.s4,
              bottom: AppPageRhythm.row,
            ),
          ),
          LifeTimeline(
            items: [
              for (final e in shownNormal)
                LifeTimelineItem(
                  id: e.id,
                  at: e.at,
                  title: e.localizedTitle(l10n),
                  subtitle: e.localizedSubtitle(l10n),
                  icon: widget.iconFor(e),
                  accent: widget.accentFor(e),
                  domainLabel: widget.domainLabel(e.domain),
                  onOpen: _onOpen(context, e),
                ),
            ],
            timeLabel: widget.timeLabel,
          ),
        ],
        if (showToggle) ...[
          const SizedBox(height: AppPageRhythm.row),
          AppRevealControl(
            expanded: _expanded,
            collapsedLabel: l10n.lifeTimelineShowMore(
              hiddenCount > 0 ? hiddenCount : 1,
            ),
            expandedLabel: l10n.lifeTimelineShowLess,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
        ],
      ],
    );
  }

  VoidCallback? _onOpen(BuildContext context, LifeEvent event) {
    if (event.actionSuggestion != null) {
      return () async {
        await showLifeSignalSheet(
          context: context,
          event: event,
          executionEnabled: widget.executionEnabled,
        );
      };
    }
    final path = event.routePath;
    return path == null ? null : () => context.go(path);
  }
}
