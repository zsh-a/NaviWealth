/// Cross-domain Life hub — spatial workbench + life timeline (Phase B + G).
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
    final formatters = context.formatters(ref);

    return ShellCanvasScaffold(
      childPad: false,
      child: SafeArea(
        bottom: false,
        child: BriefScaffold(
          greeting: _LifeGreeting(l10n: l10n),
          stage: _LifeStageCard(l10n: l10n, packCount: packs.length),
          modules: [_WorkbenchGrid(packs: packs, l10n: l10n)],
          secondary: [
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
              empty: SoftCard.raised(
                padding: AppPageRhythm.cardPadding,
                child: Text(
                  l10n.lifeTimelineEmpty,
                  style: context.bodyCaptionStyle,
                ),
              ),
              timeLabel: (at) => formatters.time(at),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(LifeEvent e) => switch (e.kind) {
    LifeEventKind.finance => FLucideIcons.wallet,
    LifeEventKind.health => FLucideIcons.heartPulse,
    LifeEventKind.knowledge => FLucideIcons.bookOpen,
    LifeEventKind.execution => FLucideIcons.listChecks,
    LifeEventKind.agent => FLucideIcons.sparkles,
    LifeEventKind.note => FLucideIcons.circle,
  };

  Color _accentFor(BuildContext context, LifeEvent e) {
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
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

class _LifeStageCard extends StatelessWidget {
  const _LifeStageCard({required this.l10n, required this.packCount});

  final AppLocalizations l10n;
  final int packCount;

  @override
  Widget build(BuildContext context) {
    return SoftCard.hero(
      padding: AppPageRhythm.heroPadding,
      onPress: AppInteraction.wrap(
        () => context.go(FinanceRoutes.home),
        intent: AppInteractionIntent.navigate,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.lifeStageTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s10),
          Text(l10n.lifeStageHeadline, style: TypographyTokens.displaySmall),
          const SizedBox(height: AppSpacing.s8),
          Text(l10n.lifeStageBody(packCount), style: context.bodyCaptionStyle),
          const SizedBox(height: AppPageRhythm.module),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.lifeOpenFinanceBrief,
                  style: context.captionLabelStyle.copyWith(
                    color: context.theme.colors.primary,
                  ),
                ),
              ),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.sm,
                color: context.theme.colors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkbenchGrid extends StatelessWidget {
  const _WorkbenchGrid({required this.packs, required this.l10n});

  final List<DomainPack> packs;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (packs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.lifeWorkbenchTitle,
          padding: const EdgeInsets.only(
            left: AppSpacing.s4,
            bottom: AppSpacing.s10,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 520;
            final children = [
              for (final pack in packs)
                _DomainWorkbenchTile(pack: pack, l10n: l10n),
            ];
            if (!wide) {
              return Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppPageRhythm.row),
                    children[i],
                  ],
                ],
              );
            }
            return Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s12,
              children: [
                for (final child in children)
                  SizedBox(
                    width: (constraints.maxWidth - AppSpacing.s12) / 2,
                    child: child,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DomainWorkbenchTile extends StatelessWidget {
  const _DomainWorkbenchTile({required this.pack, required this.l10n});

  final DomainPack pack;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final path = pack.tabPaths.isNotEmpty
        ? pack.tabPaths.first
        : FinanceRoutes.home;
    final spec = pack.shellSpecBuilder?.call(l10n);
    final label = spec?.label ?? pack.scope.wire;
    final icon = spec?.icon ?? FLucideIcons.layers;

    return SoftCard.raised(
      padding: AppPageRhythm.cardPadding,
      borderless: true,
      onPress: AppInteraction.wrap(
        () => context.go(path),
        intent: AppInteractionIntent.navigate,
      ),
      child: Row(
        children: [
          AppIconTile(icon: icon, color: colors.primary),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.rowTitleStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(l10n.lifeOpenWorkbench, style: context.captionStyle),
              ],
            ),
          ),
          Icon(
            FLucideIcons.chevronRight,
            size: AppIconSizes.h18,
            color: colors.mutedForeground.withValues(
              alpha: AppOpacity.disabled,
            ),
          ),
        ],
      ),
    );
  }
}
