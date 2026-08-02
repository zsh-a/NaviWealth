import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/core/shell/shell_visibility.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
          maxWidth: AdaptiveMaxWidth.narrow,
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
  late final FocusNode _searchFocus;
  Timer? _searchDebounce;
  String? _pendingSearchText;
  bool _searchHydrated = false;
  bool _suppressSearchChange = false;
  bool _searchOpen = false;

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
      setState(() => _pendingSearchText = null);
    });
  }

  void _clearSearch(ActivityFeedQueryController controller) {
    _searchDebounce?.cancel();
    _pendingSearchText = null;
    _syncSearchText('');
    controller.mutateQuery((q) => q.copyWith(searchText: ''));
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch(ActivityFeedQueryController controller) {
    _clearSearch(controller);
    _searchFocus.unfocus();
    setState(() => _searchOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(activityFeedQueryProvider);
    final controller = ref.read(activityFeedQueryProvider.notifier);
    final filterLabel = _filterSummary(l10n, query);

    // Hydrate the initial deep-linked query once. Afterwards panel visibility
    // remains a user choice, even while a search filter stays active.
    if (!_searchHydrated) {
      _syncSearchText(query.searchText);
      _searchOpen = query.searchText.isNotEmpty;
      _searchHydrated = true;
    } else if (_pendingSearchText == null) {
      _syncSearchText(query.searchText);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: AnimatedSwitcher(
        duration: AppMotionPolicy.duration(
          context,
          Motion.fast,
          role: AppMotionRole.transition,
        ),
        switchInCurve: Motion.standardDecelerate,
        switchOutCurve: Motion.standardAccelerate,
        child: _searchOpen
            ? Row(
                key: const ValueKey<String>('activity-search'),
                children: [
                  Expanded(
                    child: FTextField(
                      control: FTextFieldControl.managed(
                        controller: _searchController,
                        onChange: (value) =>
                            _scheduleSearch(controller, value.text),
                      ),
                      focusNode: _searchFocus,
                      textInputAction: TextInputAction.search,
                      prefixBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: AppSpacing.s12,
                          end: AppSpacing.s8,
                        ),
                        child: Icon(
                          FLucideIcons.search,
                          size: AppIconSizes.h18,
                        ),
                      ),
                      hint: l10n.activityFeedSearchHint,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  AppIconButton(
                    icon: FLucideIcons.x,
                    tooltip: l10n.commonClose,
                    onPress: () => _closeSearch(controller),
                  ),
                ],
              )
            : Row(
                key: const ValueKey<String>('activity-toolbar'),
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AppControlHeights.touchTarget,
                      ),
                      child: AppQuietButton(
                        label: filterLabel,
                        expanded: true,
                        prefix: const Icon(FLucideIcons.listFilter),
                        onPress: () => ActivityFeedFilterSheet.show(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  AppIconButton(
                    icon: FLucideIcons.search,
                    tooltip: l10n.activityFeedSearchAction,
                    onPress: _openSearch,
                  ),
                ],
              ),
      ),
    );
  }
}

String _filterSummary(AppLocalizations l10n, ActivityFeedQuery query) {
  final segments = <String>[
    activityFeedDateRangeLabel(l10n, query.dateRange),
    if (query.kinds.isEmpty)
      l10n.activityFeedFilterAllKinds
    else if (query.kinds.length == 1)
      _labelForKind(l10n, query.kinds.single)
    else
      l10n.activityFeedFilterKindCount(query.kinds.length),
    if (query.accountIds.isNotEmpty)
      l10n.activityFeedFilterAccountCount(query.accountIds.length),
  ];
  return segments.join(' · ');
}

String _labelForKind(AppLocalizations l10n, ActivityKind kind) {
  return entryKindLabel(l10n, entryKindFromActivityKind(kind));
}
