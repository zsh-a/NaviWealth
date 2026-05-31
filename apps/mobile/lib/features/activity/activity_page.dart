import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../app/shell_chrome.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../shared/entry_kind_labels.dart';
import 'data/activity_feed_provider.dart';
import 'data/activity_feed_query.dart';
import 'ui/activity_action_panel.dart';
import 'ui/activity_feed.dart';
import 'ui/activity_feed_filter_sheet.dart';

/// Activity tab — single timeline of every journal entry, with a filter
/// chip row for quickly slicing by entry kind. The legacy three-segment
/// layout (Expenses / Accounts / Feed) is gone; expenses and accounts
/// each have their own first-class detail flow now reachable via deep
/// link or the global action panel ("+").
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  bool _hydratedFromUrl = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydratedFromUrl) return;
    _hydratedFromUrl = true;
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    final query = ActivityFeedQuery.fromUri(uri);
    if (query.hasFilters) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activityFeedQueryProvider.notifier).setQuery(query);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<ActivityFeedQuery>(activityFeedQueryProvider, (_, next) {
      if (!mounted) return;
      _replaceActivityUrl(query: next);
    });

    return ShellTabScaffold(
      title: l10n.navActivity,
      childPad: false,
      actions: [
        // §5.10.10 / S5a — Layer 4 ingest review queue entry. Calm
        // by design: a plain outlined inbox, no badge/glow; the
        // pending count lives inside the review page.
        FHeaderAction(
          icon: const Icon(FLucideIcons.inbox),
          onPress: () => context.push(AppRoutes.activityIngest),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.filter),
          onPress: () => ActivityFeedFilterSheet.show(context),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          onPress: () => showActivityActionPanel(context),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 1024;
          return isDesktop
              ? AdaptiveContentFrame(
                  maxWidth: AdaptiveMaxWidth.dashboard,
                  layout: AdaptiveFrameLayout.cockpit,
                  rightRailWidth: 340,
                  primary: const ActivityFeed(),
                  secondary: _ActivityRightRail(
                    onFilter: () => ActivityFeedFilterSheet.show(context),
                    onAdd: () => showActivityActionPanel(context),
                  ),
                )
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActivityKindFilterRow(),
                    Expanded(child: ActivityFeed()),
                  ],
                );
        },
      ),
    );
  }

  void _replaceActivityUrl({required ActivityFeedQuery query}) {
    final router = GoRouter.of(context);
    final current = router.routeInformationProvider.value.uri;
    final params = <String, String>{...current.queryParameters};
    params.remove('accounts');
    params.remove('kinds');
    params.remove('from');
    params.remove('to');
    params.remove('tab');
    params.addAll(query.toQueryParameters());
    final next = current.replace(
      path: '/activity',
      queryParameters: params.isEmpty ? null : params,
    );
    if (next.toString() != current.toString()) {
      router.replace<void>(next.toString());
    }
  }
}

class _ActivityRightRail extends ConsumerWidget {
  const _ActivityRightRail({required this.onFilter, required this.onAdd});

  final VoidCallback onFilter;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(activityFeedQueryProvider);
    final controller = ref.read(activityFeedQueryProvider.notifier);
    final selected = query.kinds;
    final allActive = selected.isEmpty;
    final chips = <_KindChipSpec>[
      _KindChipSpec(
        label: l10n.activityFilterChipAll,
        active: allActive,
        onTap: () =>
            controller.setQuery(query.copyWith(kinds: const <ActivityKind>{})),
      ),
      for (final kind in const [
        ActivityKind.income,
        ActivityKind.expense,
        ActivityKind.transfer,
        ActivityKind.trade,
      ])
        _KindChipSpec(
          label: _labelForKind(l10n, kind),
          active: selected.contains(kind),
          onTap: () {
            final next = {...selected};
            if (next.contains(kind)) {
              next.remove(kind);
            } else {
              next.add(kind);
            }
            controller.setQuery(query.copyWith(kinds: next));
          },
        ),
    ];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s16, AppSpacing.s16, AppSpacing.s12),
                child: Text(
                  l10n.navActivity,
                  style: context.theme.typography.md.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final chip in chips) _FilterChip(spec: chip)],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              const FDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s12, AppSpacing.s16, 0),
                child: FButton(
                  variant: FButtonVariant.primary,
                  onPress: onAdd,
                  prefix: const Icon(FLucideIcons.plus),
                  child: Text(l10n.activityAddAction),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.s16, 0, AppSpacing.s16, AppSpacing.s16),
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: onFilter,
                  prefix: const Icon(FLucideIcons.filter),
                  child: Text(l10n.activityFeedFilterTitle),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quick filter chip row above the timeline. Tapping a chip toggles the
/// corresponding [ActivityKind] in the active feed query — multiple
/// chips can be active simultaneously. The "All" chip clears the kind
/// filter (other filters from the sheet are preserved).
class _ActivityKindFilterRow extends ConsumerWidget {
  const _ActivityKindFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(activityFeedQueryProvider);
    final controller = ref.read(activityFeedQueryProvider.notifier);
    final selected = query.kinds;
    final allActive = selected.isEmpty;

    final chips = <_KindChipSpec>[
      _KindChipSpec(
        label: l10n.activityFilterChipAll,
        active: allActive,
        onTap: () =>
            controller.setQuery(query.copyWith(kinds: const <ActivityKind>{})),
      ),
      for (final kind in const [
        ActivityKind.income,
        ActivityKind.expense,
        ActivityKind.transfer,
        ActivityKind.trade,
      ])
        _KindChipSpec(
          label: _labelForKind(l10n, kind),
          active: selected.contains(kind),
          onTap: () {
            final next = {...selected};
            if (next.contains(kind)) {
              next.remove(kind);
            } else {
              next.add(kind);
            }
            controller.setQuery(query.copyWith(kinds: next));
          },
        ),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s8),
        itemBuilder: (context, i) => _FilterChip(spec: chips[i]),
      ),
    );
  }
}

class _KindChipSpec {
  const _KindChipSpec({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.spec});

  final _KindChipSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final fg = spec.active ? colors.primaryForeground : colors.foreground;
    final bg = spec.active ? colors.primary : colors.muted;
    return FTappable(
      onPress: spec.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.s6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        alignment: Alignment.center,
        child: Text(
          spec.label,
          style: context.theme.typography.xs.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _labelForKind(AppLocalizations l10n, ActivityKind kind) {
  return entryKindLabel(l10n, entryKindFromActivityKind(kind));
}
