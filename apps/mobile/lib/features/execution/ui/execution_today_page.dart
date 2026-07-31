import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as execution_agent_providers;
import '../composition/execution_route_paths.dart';
import '../data/execution_daily_focus.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_action_card_controller.dart';
import 'execution_action_sheet.dart';
import 'execution_progress_sheet.dart';
import 'execution_search_sheet.dart';
import 'execution_source_route.dart';
import 'execution_widgets.dart';

class ExecutionTodayPage extends ConsumerWidget {
  const ExecutionTodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionTodayTitle,
      directActionBudget: 1,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.search,
          label: l10n.executionSearchTitle,
          onPress: () => showExecutionSearchSheet(context: context),
          order: -10,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.executionCreateActionTitle,
          onPress: () => showExecutionActionSheet(context: context),
        ),
      ],
      child: ShellTabPause(
        routePath: ExecutionRoutes.today,
        child: _TodayList(),
      ),
    );
  }
}

class _TodayList extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TodayList> createState() => _TodayListState();
}

class _TodayListState extends ConsumerState<_TodayList> {
  ExecutionTodayFilter _filter = ExecutionTodayFilter.focus;

  Future<void> _refresh() async {
    ref.invalidate(executionTodayActionsProvider);
    ref.invalidate(executionOpenActionsProvider);
    ref.invalidate(executionProjectsProvider);
    ref.invalidate(executionCommitmentsProvider);
    ref.invalidate(executionRecentProgressProvider);
    ref.invalidate(executionActionRelationsProvider);
    await ref.read(executionTodayActionsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actionsAsync = ref.watch(executionTodayActionsProvider);
    final openActionsAsync = ref.watch(executionOpenActionsProvider);
    final projectsAsync = ref.watch(executionProjectsProvider);
    final commitmentsAsync = ref.watch(executionCommitmentsProvider);
    final progressAsync = ref.watch(executionRecentProgressProvider);
    final relations = ref.watch(executionActionRelationsProvider).value;
    final focusIds = ref.watch(executionDailyFocusProvider);
    ref.listen(
      execution_agent_providers.latestExecutionReviewArtifactProvider,
      (_, next) {
        next.whenData((artifact) {
          if (artifact == null) return;
          final insight = artifact.insights
              .where((item) => item.id == 'today_focus')
              .firstOrNull;
          final raw = insight?.payload['recommended_focus_ids'];
          if (raw is! List) return;
          ref
              .read(executionDailyFocusProvider.notifier)
              .adoptRecommendedIfEmpty(raw.whereType<String>());
        });
      },
    );
    return actionsAsync.when(
      loading: () =>
          AppListPageSkeleton(padding: shellTabContentPadding(context)),
      error: (error, stackTrace) => kDefaultError(
        context,
        error,
        stackTrace,
        onRetry: () => ref.invalidate(executionTodayActionsProvider),
      ),
      data: (actions) {
        final now = DateTime.now();
        final openActions = openActionsAsync.value ?? actions;
        final projects = projectsAsync.value ?? const <ExecutionProject>[];
        final commitments =
            commitmentsAsync.value ?? const <ExecutionCommitment>[];
        final recentProgress =
            progressAsync.value ?? const <ExecutionProgressEntry>[];
        final filteredActions = filteredExecutionActions(
          filter: _filter,
          todayActions: actions,
          openActions: openActions,
        );
        final visibleActions = filteredActions.toList()
          ..sort((a, b) {
            final aIndex = focusIds.indexOf(a.id);
            final bIndex = focusIds.indexOf(b.id);
            if (aIndex >= 0 && bIndex >= 0) return aIndex.compareTo(bIndex);
            if (aIndex >= 0) return -1;
            if (bIndex >= 0) return 1;
            return 0;
          });
        final snapshot = ExecutionOverviewSnapshot.fromLists(
          todayActions: actions,
          openActions: openActions,
          projects: projects,
          commitments: commitments,
          recentProgress: recentProgress,
          now: now,
        );

        final actionModules = <Widget>[
          _DailyFocusPanel(actions: openActions, selectedIds: focusIds),
          if (visibleActions.isEmpty)
            ExecutionStateView(
              icon: _filter == ExecutionTodayFilter.focus
                  ? FLucideIcons.checkCheck
                  : executionTodayFilterIcon(_filter),
              title: _filter == ExecutionTodayFilter.focus
                  ? l10n.executionTodayEmptyTitle
                  : l10n.executionTodayFilteredEmptyTitle,
              message: _filter == ExecutionTodayFilter.focus
                  ? l10n.executionTodayEmptyBody
                  : l10n.executionTodayFilteredEmptyBody,
              action: _filter == ExecutionTodayFilter.focus
                  ? FButton(
                      onPress: () => showExecutionActionSheet(context: context),
                      child: Text(l10n.executionCreateActionTitle),
                    )
                  : null,
            )
          else ...[
            ExecutionSectionHeader(
              title: executionTodayFilterLabel(l10n, _filter),
              count: visibleActions.length,
              icon: executionTodayFilterIcon(_filter),
            ),
            for (final action in visibleActions)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppFilterChip(
                      label: l10n.executionDailyFocusToggle,
                      active: focusIds.contains(action.id),
                      onPress: () => ref
                          .read(executionDailyFocusProvider.notifier)
                          .toggle(action.id),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  ExecutionActionCardController(
                    action: action,
                    projectLabel:
                        relations?.projectLabel(action.projectId) ??
                        executionProjectRelationLabel(
                          projects,
                          action.projectId,
                        ),
                    commitmentLabel:
                        relations?.commitmentLabel(action.commitmentId) ??
                        executionCommitmentRelationLabel(
                          commitments,
                          action.commitmentId,
                        ),
                    onOpen: () =>
                        context.push(ExecutionRoutes.action(action.id)),
                    onSourceOpen: executionSourceOpen(
                      context,
                      ref,
                      action.source,
                    ),
                    onEdit: () => showExecutionActionSheet(
                      context: context,
                      action: action,
                    ),
                    onRecordProgress: () => showExecutionProgressSheet(
                      context: context,
                      action: action,
                    ),
                    blockedProgressNote: l10n.executionProgressBlockedDefault,
                    doneProgressNote: l10n.executionProgressDoneDefault,
                    droppedProgressNote: l10n.executionProgressDroppedDefault,
                  ),
                ],
              ),
          ],
        ];

        return BriefScaffold(
          padding: shellTabContentPadding(context),
          onRefresh: _refresh,
          greeting: const SizedBox.shrink(),
          stage: AppCollapsingStage(
            child: ExecutionOverviewStrip(
              snapshot: snapshot,
              selectedFilter: _filter,
              onFilterChanged: (filter) => setState(() => _filter = filter),
            ),
          ),
          stickyBuilder: (context, progress) {
            final subtitle = snapshot.blockedCount > 0
                ? '${l10n.executionOverviewBlocked} ${snapshot.blockedCount}'
                : l10n.executionOverviewFocus;
            return AppCollapsedSummaryBar(
              progress: progress,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.executionOverviewFocus,
                      style: context.mutedLabelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${snapshot.todayCount}',
                    style: TypographyTokens.numericTitleStrong,
                  ),
                  if (snapshot.blockedCount > 0) ...[
                    const SizedBox(width: AppSpacing.s8),
                    AppBadge(
                      label: subtitle,
                      size: AppBadgeSize.compact,
                      tone: AppBadgeTone.warning,
                    ),
                  ],
                ],
              ),
            );
          },
          secondary: actionModules,
        );
      },
    );
  }
}

class _DailyFocusPanel extends ConsumerWidget {
  const _DailyFocusPanel({required this.actions, required this.selectedIds});

  final List<ExecutionAction> actions;
  final List<String> selectedIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final byId = <String, ExecutionAction>{
      for (final action in actions) action.id: action,
    };
    final selected = selectedIds
        .map((id) => byId[id])
        .whereType<ExecutionAction>()
        .toList(growable: false);
    return SoftCard(
      level: SoftCardLevel.raised,
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppMetricHeader(
            icon: FLucideIcons.target,
            title: l10n.executionDailyFocusTitle,
            color: context.appTheme.status.info.fg,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            selected.isEmpty
                ? l10n.executionDailyFocusEmpty
                : selected.map((action) => action.title).join(' · '),
            style: context.captionStyle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
