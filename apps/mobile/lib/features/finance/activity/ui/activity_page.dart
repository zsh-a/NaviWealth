import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/core/shell/shell_visibility.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../shared/l10n/account_l10n.dart';
import '../../shared/l10n/entry_kind_labels.dart';
import '../data/activity_feed_provider.dart';
import '../data/activity_feed_query.dart';
import 'activity_action_panel.dart';
import 'activity_feed.dart';
import 'activity_feed_filter_sheet.dart';

/// Activity tab — single timeline of every journal entry.
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  String? _hydratedLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    if (uri.path != FinanceRoutes.activity) return;
    final location = uri.toString();
    if (_hydratedLocation == location) return;
    _hydratedLocation = location;
    final query = ActivityFeedQuery.fromUri(uri);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(activityFeedQueryProvider.notifier).setQuery(query);
    });
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
      directActionBudget: 1,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.activityAddAction,
          onPress: () => showActivityActionPanel(context),
          order: 0,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.chartColumnStacked,
          label: l10n.cashFlowTitle,
          onPress: () => context.push(FinanceRoutes.cashflow),
          order: 20,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.inbox,
          label: l10n.ingestReviewTitle,
          onPress: () => context.push(FinanceRoutes.activityIngest),
          order: 30,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.pieChart,
          label: l10n.spendingTitle,
          onPress: () => context.push(FinanceRoutes.spending),
          order: 40,
        ),
      ],
      child: const ShellTabPause(
        routePath: FinanceRoutes.activity,
        placeholder: ActivityFeedSkeleton(),
        child: AdaptiveContentFrame(
          maxWidth: AdaptiveMaxWidth.dashboard,
          expandSinglePrimary: true,
          padding: EdgeInsets.zero,
          primary: Column(
            children: [
              _ActivityFilterBar(),
              Expanded(child: ActivityFeed()),
            ],
          ),
        ),
      ),
    );
  }

  void _replaceActivityUrl({required ActivityFeedQuery query}) {
    final router = GoRouter.of(context);
    final current = router.routeInformationProvider.value.uri;
    if (current.path != FinanceRoutes.activity) return;
    final params = <String, String>{...current.queryParameters};
    params.remove('accounts');
    params.remove('kinds');
    params.remove('from');
    params.remove('to');
    params.remove('q');
    params.remove('tab');
    params.addAll(query.toQueryParameters());
    final next = current.replace(
      path: FinanceRoutes.activity,
      queryParameters: params.isEmpty ? null : params,
    );
    if (next.toString() != current.toString()) {
      router.replace<void>(next.toString());
    }
  }
}

class _ActivityFilterBar extends ConsumerStatefulWidget {
  const _ActivityFilterBar();

  @override
  ConsumerState<_ActivityFilterBar> createState() => _ActivityFilterBarState();
}

class _ActivityFilterBarState extends ConsumerState<_ActivityFilterBar> {
  static const _searchDebounceDuration = Duration(milliseconds: 220);

  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  String? _pendingSearchText;
  bool _searchHydrated = false;
  bool _suppressSearchChange = false;
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _syncSearchText(String value) {
    if (_searchController.text == value) return;
    _suppressSearchChange = true;
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _suppressSearchChange = false;
  }

  void _scheduleSearch(ActivityFeedQueryController controller, String value) {
    if (_suppressSearchChange) return;
    _searchDebounce?.cancel();
    _pendingSearchText = value;
    _searchDebounce = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      controller.mutateQuery((q) => q.copyWith(searchText: value));
      setState(() => _pendingSearchText = null);
    });
  }

  void _clearSearch(ActivityFeedQueryController controller) {
    _searchDebounce?.cancel();
    _pendingSearchText = null;
    _syncSearchText('');
    controller.mutateQuery((q) => q.copyWith(searchText: ''));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(activityFeedQueryProvider);
    final controller = ref.read(activityFeedQueryProvider.notifier);
    final selected = query.kinds;
    final allActive = selected.isEmpty;
    final sheetFilterCount =
        (query.dateRange == null ? 0 : 1) + query.accountIds.length;
    final filterLabel = sheetFilterCount == 0
        ? l10n.activityFeedFilterTitle
        : '${l10n.activityFeedFilterTitle} · $sheetFilterCount';

    // Hydrate the initial deep-linked query once. Afterwards panel visibility
    // remains a user choice, even while a search filter stays active.
    if (!_searchHydrated) {
      _syncSearchText(query.searchText);
      _searchOpen = query.searchText.isNotEmpty;
      _searchHydrated = true;
    } else if (_pendingSearchText == null) {
      _syncSearchText(query.searchText);
    }

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
            AppInteraction.signal(AppInteractionIntent.select);
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [for (final chip in chips) _FilterChip(spec: chip)],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppIconButton(
                icon: FLucideIcons.search,
                tooltip: l10n.activityFeedSearchAction,
                onPress: () => setState(() => _searchOpen = !_searchOpen),
              ),
              AppIconButton(
                icon: FLucideIcons.slidersHorizontal,
                tooltip: filterLabel,
                onPress: () => ActivityFeedFilterSheet.show(context),
              ),
            ],
          ),
          if (_searchOpen) ...[
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: _searchController,
                      onChange: (value) =>
                          _scheduleSearch(controller, value.text),
                    ),
                    hint: l10n.activityFeedSearchHint,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                AppIconButton(
                  icon: FLucideIcons.x,
                  tooltip: l10n.activityFeedFilterClear,
                  onPress: () => _clearSearch(controller),
                ),
              ],
            ),
          ],
          if (query.hasSheetFilters || query.searchText.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            _ActiveFilterTags(query: query),
          ],
        ],
      ),
    );
  }
}

class _ActiveFilterTags extends ConsumerWidget {
  const _ActiveFilterTags({required this.query});

  final ActivityFeedQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(activityFeedQueryProvider.notifier);
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final byId = {for (final a in accounts) a.id: a};
    final tags = <Widget>[];

    if (query.searchText.trim().isNotEmpty) {
      tags.add(
        AppFilterChip(
          label: l10n.activityFeedSearchTag(query.searchText.trim()),
          active: true,
          onPress: null,
          onClear: () =>
              controller.mutateQuery((q) => q.copyWith(searchText: '')),
          icon: FLucideIcons.search,
        ),
      );
    }
    if (query.dateRange != null) {
      tags.add(
        AppFilterChip(
          label: l10n.activityFeedFilterDateRange,
          active: true,
          onPress: () => ActivityFeedFilterSheet.show(context),
          onClear: () =>
              controller.mutateQuery((q) => q.copyWith(dateRange: null)),
          icon: FLucideIcons.calendar,
        ),
      );
    }
    for (final id in query.accountIds) {
      final name = byId[id] != null
          ? localizedAccountName(l10n, byId[id]!)
          : id;
      tags.add(
        AppFilterChip(
          label: name,
          active: true,
          onPress: () => ActivityFeedFilterSheet.show(context),
          onClear: () {
            controller.mutateQuery((q) {
              final ids = {...q.accountIds}..remove(id);
              return q.copyWith(accountIds: ids);
            });
          },
          icon: FLucideIcons.wallet,
        ),
      );
    }

    if (tags.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tags.length; i++) ...[
            tags[i],
            if (i < tags.length - 1) const SizedBox(width: AppSpacing.s8),
          ],
        ],
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

void _setActivityKinds(
  ActivityFeedQueryController controller,
  ActivityFeedQuery query,
  Set<ActivityKind> kinds,
) {
  AppInteraction.signal(AppInteractionIntent.select);
  controller.setQuery(query.copyWith(kinds: kinds));
}
