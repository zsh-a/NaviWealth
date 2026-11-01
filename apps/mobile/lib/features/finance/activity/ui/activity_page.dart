import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/core/shell/shell_visibility.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../shared/l10n/entry_kind_labels.dart';
import '../data/activity_feed_provider.dart';
import '../data/activity_feed_query.dart';
import 'activity_action_panel.dart';
import 'activity_entry_detail_page.dart';
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
          icon: FLucideIcons.fileInput,
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
      child: ShellTabPause(
        routePath: FinanceRoutes.activity,
        placeholder: const ActivityFeedSkeleton(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            Widget feed({ValueChanged<String>? onEntryOpen}) =>
                AdaptiveContentFrame(
                  maxWidth: AdaptiveMaxWidth.narrow,
                  expandSinglePrimary: true,
                  padding: EdgeInsets.zero,
                  primary: Column(
                    children: [
                      const _ActivityFilterBar(),
                      Expanded(child: ActivityFeed(onEntryOpen: onEntryOpen)),
                    ],
                  ),
                );
            if (GoRouter.maybeOf(context) == null ||
                !MasterDetailLayout.shouldUseMasterDetail(
                  constraints.maxWidth,
                )) {
              return feed();
            }
            final selected = selectedQueryOf(context);
            return MasterDetailLayout(
              master: feed(
                onEntryOpen: (entryId) => replaceSelectedQuery(
                  context,
                  path: FinanceRoutes.activity,
                  selected: entryId,
                ),
              ),
              detail: selected == null
                  ? MasterDetailEmpty(
                      message: l10n.activitySelectEntry,
                      icon: FLucideIcons.receiptText,
                    )
                  : ActivityEntryDetailRoute(entryId: selected),
            );
          },
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
  late final FocusNode _searchFocus;
  Timer? _searchDebounce;
  String? _pendingSearchText;
  bool _suppressSearchChange = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
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
      _pendingSearchText = null;
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
    final feed = ref.watch(activityFeedProvider);
    final page = feed.value;
    if (_pendingSearchText == null) _syncSearchText(query.searchText);

    void clearFilters() => controller.mutateQuery(
      (q) => q.copyWith(
        dateRange: null,
        kinds: const <ActivityKind>{},
        accountIds: const <String>{},
      ),
    );

    Widget facet(ActivityFilterSection section, String label, bool active) =>
        AppFilterChip.trigger(
          key: ValueKey('activity-filter-${section.name}'),
          label: label,
          active: active,
          onPress: () =>
              ActivityFeedFilterSheet.show(context, section: section),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: _searchController,
                  onChanged: (text) => text.isEmpty
                      ? _clearSearch(controller)
                      : _scheduleSearch(controller, text),
                  focusNode: _searchFocus,
                  hint: l10n.activityFeedSearchHint,
                  clearLabel: l10n.aiChatSessionsSearchClear,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppIconButton(
                key: const ValueKey('activity-filter-all'),
                icon: FLucideIcons.listFilter,
                tooltip: l10n.activityFeedFilterTitle,
                surface: query.hasSheetFilters
                    ? AppIconButtonSurface.softSelected
                    : AppIconButtonSurface.plain,
                onPress: () => ActivityFeedFilterSheet.show(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s6,
            children: [
              facet(
                ActivityFilterSection.date,
                l10n.activityFeedFilterDateRange,
                query.dateRange != null,
              ),
              facet(
                ActivityFilterSection.kind,
                query.kinds.length <= 1
                    ? l10n.activityFeedFilterKind
                    : l10n.activityFeedFilterKindCount(query.kinds.length),
                query.kinds.isNotEmpty,
              ),
              facet(
                ActivityFilterSection.account,
                query.accountIds.length <= 1
                    ? l10n.activityFeedFilterAccount
                    : l10n.activityFeedFilterAccountCount(
                        query.accountIds.length,
                      ),
                query.accountIds.isNotEmpty,
              ),
            ],
          ),
          if (query.hasSheetFilters) ...[
            const SizedBox(height: AppSpacing.s4),
            // Keep the toolbar bounded even with many selected accounts.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (query.dateRange != null)
                    _filterChip(
                      l10n,
                      ActivityFilterSection.date,
                      activityFeedDateRangeLabel(l10n, query.dateRange),
                      () => controller.mutateQuery(
                        (q) => q.copyWith(dateRange: null),
                      ),
                    ),
                  for (final kind in query.kinds)
                    _filterChip(
                      l10n,
                      ActivityFilterSection.kind,
                      _labelForKind(l10n, kind),
                      () => controller.mutateQuery(
                        (q) => q.copyWith(kinds: {...q.kinds}..remove(kind)),
                      ),
                    ),
                  for (final id in query.accountIds)
                    _filterChip(
                      l10n,
                      ActivityFilterSection.account,
                      page?.accountsById[id]?.name ??
                          l10n.activityFeedFilterAccount,
                      () => controller.mutateQuery(
                        (q) => q.copyWith(
                          accountIds: {...q.accountIds}..remove(id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (query.hasSheetFilters)
            Wrap(
              spacing: AppSpacing.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (page != null && !feed.isLoading && !feed.hasError)
                  Text(
                    l10n.commonSearchResultsCount(page.totalCount),
                    style: context.captionStyle,
                  ),
                AppQuietButton(
                  label: l10n.activityFeedFilterClear,
                  onPress: AppInteraction.wrap(
                    clearFilters,
                    intent: AppInteractionIntent.select,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _filterChip(
    AppLocalizations l10n,
    ActivityFilterSection section,
    String label,
    VoidCallback onClear,
  ) => Padding(
    padding: const EdgeInsetsDirectional.only(end: AppSpacing.s6),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: AppFilterChip(
        label: label,
        active: true,
        onPress: () => ActivityFeedFilterSheet.show(context, section: section),
        onClear: onClear,
        clearSemanticLabel: '${l10n.activityFeedFilterClear}: $label',
      ),
    ),
  );
}

String _labelForKind(AppLocalizations l10n, ActivityKind kind) {
  return entryKindLabel(l10n, entryKindFromActivityKind(kind));
}
