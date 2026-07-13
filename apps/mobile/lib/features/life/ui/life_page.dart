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
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
          stage: _LifeHero(l10n: l10n, summary: hero),
          modules: [
            if (packs.isNotEmpty) _WorkspaceChips(packs: packs, l10n: l10n),
          ],
          secondary: [
            if (events.isEmpty)
              SoftCard.raised(
                padding: AppPageRhythm.cardPadding,
                borderless: true,
                child: Text(
                  l10n.lifeTimelineEmpty,
                  style: context.bodyCaptionStyle,
                ),
              )
            else ...[
              SectionHeader(
                title: l10n.lifeTimelineTitle,
                padding: const EdgeInsets.only(
                  left: AppSpacing.s4,
                  bottom: AppSpacing.s8,
                ),
              ),
              LifeTimeline(
                items: [
                  for (final e in events)
                    LifeTimelineItem(
                      id: e.id,
                      at: e.at,
                      title: e.localizedTitle(l10n),
                      subtitle: e.localizedSubtitle(l10n),
                      icon: _iconFor(e),
                      accent: _accentFor(context, e),
                      domainLabel: _domainLabel(l10n, e.domain),
                      onOpen: e.routePath == null
                          ? null
                          : () {
                              AppInteraction.signal(
                                AppInteractionIntent.navigate,
                              );
                              context.go(e.routePath!);
                            },
                    ),
                ],
                timeLabel: (at) => formatters.time(at),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(LifeEvent e) => switch (e.template) {
    LifeEventTemplate.financeDaySummary => FLucideIcons.receipt,
    LifeEventTemplate.recoveryAlert => FLucideIcons.heartPulse,
    LifeEventTemplate.executionBlocked => FLucideIcons.octagonAlert,
    LifeEventTemplate.executionDue => FLucideIcons.calendarClock,
    LifeEventTemplate.knowledgeInbox => FLucideIcons.inbox,
    LifeEventTemplate.agentResult => FLucideIcons.sparkles,
  };

  Color _accentFor(BuildContext context, LifeEvent e) {
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

  String _domainLabel(AppLocalizations l10n, DomainScope scope) =>
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

class _LifeHero extends StatelessWidget {
  const _LifeHero({required this.l10n, required this.summary});

  final AppLocalizations l10n;
  final LifeHeroSummary summary;

  @override
  Widget build(BuildContext context) {
    return SoftCard.hero(
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.lifeStageTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s10),
          Text(
            summary.localizedHeadline(l10n),
            style: TypographyTokens.displaySmall,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(summary.localizedBody(l10n), style: context.bodyCaptionStyle),
        ],
      ),
    );
  }
}

/// Compact horizontal domain chips — replaces the large workbench card wall.
class _WorkspaceChips extends StatelessWidget {
  const _WorkspaceChips({required this.packs, required this.l10n});

  final List<DomainPack> packs;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.lifeWorkbenchTitle,
          padding: const EdgeInsets.only(
            left: AppSpacing.s4,
            bottom: AppSpacing.s8,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < packs.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.s8),
                _DomainChip(pack: packs[i], l10n: l10n, colors: colors),
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
  });

  final DomainPack pack;
  final AppLocalizations l10n;
  final FColors colors;

  @override
  Widget build(BuildContext context) {
    final path = pack.tabPaths.isNotEmpty
        ? pack.tabPaths.first
        : FinanceRoutes.home;
    final spec = pack.shellSpecBuilder?.call(l10n);
    final label = spec?.label ?? pack.scope.wire;
    final icon = spec?.icon ?? FLucideIcons.layers;

    return SoftCard.raised(
      borderless: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      onPress: AppInteraction.wrap(
        () => context.go(path),
        intent: AppInteractionIntent.navigate,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppIconSizes.sm, color: colors.primary),
          const SizedBox(width: AppSpacing.s8),
          Text(label, style: context.labelStyle),
        ],
      ),
    );
  }
}
