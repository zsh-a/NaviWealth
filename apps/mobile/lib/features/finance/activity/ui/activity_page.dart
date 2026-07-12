import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../shared/l10n/entry_kind_labels.dart';
import '../data/activity_feed_provider.dart';
import '../data/activity_feed_query.dart';
import 'activity_action_panel.dart';
import 'activity_feed.dart';
import 'activity_feed_filter_sheet.dart';

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
    final isDesktop =
        MediaQuery.sizeOf(context).width >= Breakpoints.contentTwoColumn;
    final activeFilterCount = _activityFilterCount(
      ref.watch(activityFeedQueryProvider),
    );
    ref.listen<ActivityFeedQuery>(activityFeedQueryProvider, (_, next) {
      if (!mounted) return;
      _replaceActivityUrl(query: next);
    });

    return ShellTabScaffold(
      title: l10n.navActivity,
      childPad: false,
      directActionBudget: isDesktop ? 2 : 1,
      actions: [
        // §5.10.10 / S5a — Layer 4 ingest review queue entry. Calm
        // by design: a plain outlined inbox, no badge/glow; the
        // pending count lives inside the review page.
        ShellHeaderActionSpec(
          icon: FLucideIcons.inbox,
          label: l10n.ingestReviewTitle,
          onPress: () => context.push(FinanceRoutes.activityIngest),
          order: 20,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.receipt,
          label: l10n.activityExpenseListLink,
          onPress: () => context.push(FinanceRoutes.activityExpenses),
          order: 30,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.pieChart,
          label: l10n.activityExpenseReportLink,
          onPress: () => context.push(FinanceRoutes.expenseReport),
          order: 40,
        ),
        if (!isDesktop) ...[
          ShellHeaderActionSpec(
            icon: FLucideIcons.filter,
            label: l10n.activityFeedFilterTitle,
            onPress: () => ActivityFeedFilterSheet.show(context),
            order: 10,
            badgeCount: activeFilterCount,
          ),
        ],
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          return isDesktop
              ? AdaptiveContentFrame(
                  maxWidth: AdaptiveMaxWidth.dashboard,
                  layout: AdaptiveFrameLayout.cockpit,
                  // A 1280 window leaves 984dp after the domain dock and
                  // expanded tab sidebar, still enough for a 620dp feed plus
                  // this 340dp rail. Keep the cockpit instead of stacking two
                  // independently scrolling surfaces.
                  columnBreakpoint: 960,
                  rightRailWidth: kAdaptiveRightRailWidth,
                  primary: const ActivityFeed(),
                  secondary: _ActivityRightRail(
                    onFilter: () => ActivityFeedFilterSheet.show(context),
                    onAdd: () => showActivityActionPanel(context),
                  ),
                )
              : Stack(
                  children: [
                    const Positioned.fill(child: ActivityFeed()),
                    PositionedDirectional(
                      end: AppSpacing.s16,
                      bottom: shellTabFloatingActionBottom(context),
                      child: _ActivityPrimaryAction(
                        onPress: () => showActivityActionPanel(context),
                      ),
                    ),
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

class _ActivityPrimaryAction extends StatelessWidget {
  const _ActivityPrimaryAction({required this.onPress});

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.full)),
        boxShadow: AppShadow.elevation2,
      ),
      child: AppActionButton(
        onPress: onPress,
        mainAxisSize: MainAxisSize.min,
        prefix: const Icon(FLucideIcons.plus),
        child: Text(AppLocalizations.of(context).activityAddAction),
      ),
    );
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
    final activeFilterCount = _activityFilterCount(query);
    final filterLabel = activeFilterCount == 0
        ? l10n.activityFeedFilterTitle
        : '${l10n.activityFeedFilterTitle} · $activeFilterCount';
    final chips = <_KindChipSpec>[
      _KindChipSpec(
        label: l10n.activityFilterChipAll,
        active: allActive,
        onTap: () =>
            _setActivityKinds(controller, query, const <ActivityKind>{}),
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
            Haptics.selection();
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  AppSpacing.s16,
                  AppSpacing.s16,
                  AppSpacing.s12,
                ),
                child: Text(l10n.navActivity, style: context.rowTitleStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                child: Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [for (final chip in chips) _FilterChip(spec: chip)],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              const SizedBox(height: AppSpacing.s12),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  0,
                  AppSpacing.s16,
                  0,
                ),
                child: FButton(
                  variant: FButtonVariant.primary,
                  onPress: onAdd,
                  prefix: const Icon(FLucideIcons.plus),
                  child: Text(l10n.activityAddAction),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  0,
                  AppSpacing.s16,
                  AppSpacing.s16,
                ),
                child: AppQuietButton(
                  label: filterLabel,
                  onPress: onFilter,
                  expanded: true,
                  prefix: const Icon(FLucideIcons.filter),
                ),
              ),
            ],
          ),
        ),
      ],
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
    return AppFilterChip(
      label: spec.label,
      active: spec.active,
      onPress: spec.onTap,
    );
  }
}

String _labelForKind(AppLocalizations l10n, ActivityKind kind) {
  return entryKindLabel(l10n, entryKindFromActivityKind(kind));
}

int _activityFilterCount(ActivityFeedQuery query) {
  return query.kinds.length +
      query.accountIds.length +
      (query.dateRange == null ? 0 : 1);
}

void _setActivityKinds(
  ActivityFeedQueryController controller,
  ActivityFeedQuery query,
  Set<ActivityKind> kinds,
) {
  Haptics.selection();
  controller.setQuery(query.copyWith(kinds: kinds));
}
