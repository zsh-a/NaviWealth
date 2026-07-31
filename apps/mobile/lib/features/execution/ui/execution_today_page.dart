import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact.dart';
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
    final reviewArtifact = ref
        .watch(execution_agent_providers.latestExecutionReviewArtifactProvider)
        .value;
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
        if (openActionsAsync.value case final loadedOpenActions?) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref
                .read(executionDailyFocusProvider.notifier)
                .retainExisting(loadedOpenActions.map((action) => action.id));
          });
        }
        final filteredActions = filteredExecutionActions(
          filter: _filter,
          todayActions: actions,
          openActions: openActions,
        );
        final visibleActions =
            filteredActions
                .where(
                  (action) =>
                      _filter != ExecutionTodayFilter.focus ||
                      !focusIds.contains(action.id),
                )
                .toList()
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
        final suggestedFocus = focusIds.isEmpty
            ? _recommendedFocusActions(reviewArtifact, openActions)
            : const <ExecutionAction>[];

        final actionModules = <Widget>[
          _DailyFocusPanel(
            actions: openActions,
            selectedIds: focusIds,
            suggestedActions: suggestedFocus,
            onAdoptSuggestions: suggestedFocus.isEmpty
                ? null
                : () => ref
                      .read(executionDailyFocusProvider.notifier)
                      .set(suggestedFocus.map((action) => action.id)),
            onOpen: (action) => context.push(ExecutionRoutes.action(action.id)),
          ),
          if (visibleActions.isEmpty) ...[
            if (!(_filter == ExecutionTodayFilter.focus && focusIds.isNotEmpty))
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
                        onPress: () =>
                            showExecutionActionSheet(context: context),
                        child: Text(l10n.executionCreateActionTitle),
                      )
                    : null,
              ),
          ] else ...[
            ExecutionSectionHeader(
              title: _filter == ExecutionTodayFilter.focus
                  ? l10n.executionTodayNextActions
                  : executionTodayFilterLabel(l10n, _filter),
              count: visibleActions.length,
              icon: executionTodayFilterIcon(_filter),
            ),
            for (final action in visibleActions)
              ExecutionActionCardController(
                action: action,
                projectLabel:
                    relations?.projectLabel(action.projectId) ??
                    executionProjectRelationLabel(projects, action.projectId),
                commitmentLabel:
                    relations?.commitmentLabel(action.commitmentId) ??
                    executionCommitmentRelationLabel(
                      commitments,
                      action.commitmentId,
                    ),
                onOpen: () => context.push(ExecutionRoutes.action(action.id)),
                onSourceOpen: executionSourceOpen(context, ref, action.source),
                onEdit: () =>
                    showExecutionActionSheet(context: context, action: action),
                onRecordProgress: () => showExecutionProgressSheet(
                  context: context,
                  action: action,
                ),
                doneProgressNote: l10n.executionProgressDoneDefault,
                droppedProgressNote: l10n.executionProgressDroppedDefault,
                focusSelected: focusIds.contains(action.id),
                onToggleFocus: () => _toggleFocus(action, openActions),
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

  Future<void> _toggleFocus(
    ExecutionAction action,
    List<ExecutionAction> openActions,
  ) async {
    final controller = ref.read(executionDailyFocusProvider.notifier);
    if (await controller.toggle(action.id) || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final selectedIds = ref.read(executionDailyFocusProvider);
    final byId = <String, ExecutionAction>{
      for (final item in openActions) item.id: item,
    };
    await showAppSheet<void>(
      context: context,
      title: l10n.executionDailyFocusReplaceTitle,
      subtitle: l10n.executionDailyFocusReplaceBody(action.title),
      builder: (sheetContext) => AppActionSheetList(
        children: [
          for (final id in selectedIds)
            if (byId[id] case final selected?)
              AppActionSheetTile(
                icon: FLucideIcons.refreshCw,
                title: selected.title,
                subtitle: l10n.executionDailyFocusReplaceAction,
                onPress: () {
                  Navigator.of(sheetContext).pop();
                  controller.replace(selected.id, action.id);
                },
              ),
        ],
      ),
    );
  }
}

class _DailyFocusPanel extends ConsumerWidget {
  const _DailyFocusPanel({
    required this.actions,
    required this.selectedIds,
    required this.suggestedActions,
    required this.onAdoptSuggestions,
    required this.onOpen,
  });

  final List<ExecutionAction> actions;
  final List<String> selectedIds;
  final List<ExecutionAction> suggestedActions;
  final VoidCallback? onAdoptSuggestions;
  final ValueChanged<ExecutionAction> onOpen;

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
            trailing: AppBadge(
              label: l10n.executionDailyFocusCount(selected.length),
              size: AppBadgeSize.compact,
              tone: selected.length == 3
                  ? AppBadgeTone.info
                  : AppBadgeTone.neutral,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (selected.isEmpty) ...[
            Text(l10n.executionDailyFocusEmpty, style: context.captionStyle),
            if (suggestedActions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s10),
              AppStatusBanner(
                compact: true,
                kind: AppStatusKind.info,
                icon: FLucideIcons.sparkles,
                message: l10n.executionDailyFocusSuggestion(
                  suggestedActions.map((action) => action.title).join(' · '),
                ),
                action: FButton(
                  variant: FButtonVariant.ghost,
                  onPress: onAdoptSuggestions,
                  child: Text(l10n.executionDailyFocusUseSuggestion),
                ),
              ),
            ],
          ] else
            for (var index = 0; index < selected.length; index++)
              _DailyFocusRow(
                index: index,
                action: selected[index],
                count: selected.length,
                onOpen: () => onOpen(selected[index]),
                onMove: (offset) => ref
                    .read(executionDailyFocusProvider.notifier)
                    .move(selected[index].id, offset),
                onRemove: () => ref
                    .read(executionDailyFocusProvider.notifier)
                    .toggle(selected[index].id),
              ),
        ],
      ),
    );
  }
}

List<ExecutionAction> _recommendedFocusActions(
  AgentArtifact? artifact,
  List<ExecutionAction> openActions,
) {
  final insight = artifact?.insights
      .where((item) => item.id == 'today_focus')
      .firstOrNull;
  final raw = insight?.payload['recommended_focus_ids'];
  if (raw is! List) return const <ExecutionAction>[];
  final ids = raw.whereType<String>().take(3).toList(growable: false);
  final byId = <String, ExecutionAction>{
    for (final action in openActions) action.id: action,
  };
  return ids.map((id) => byId[id]).whereType<ExecutionAction>().toList();
}

class _DailyFocusRow extends StatelessWidget {
  const _DailyFocusRow({
    required this.index,
    required this.action,
    required this.count,
    required this.onOpen,
    required this.onMove,
    required this.onRemove,
  });

  final int index;
  final ExecutionAction action;
  final int count;
  final VoidCallback onOpen;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: Row(
        children: [
          AppBadge(
            label: '${index + 1}',
            size: AppBadgeSize.compact,
            tone: AppBadgeTone.info,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
                child: Text(
                  action.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: FLucideIcons.arrowUp,
            tooltip: l10n.executionDailyFocusMoveUp,
            onPress: index == 0 ? null : () => onMove(-1),
            size: 32,
            iconSize: AppIconSizes.xs,
          ),
          AppIconButton(
            icon: FLucideIcons.arrowDown,
            tooltip: l10n.executionDailyFocusMoveDown,
            onPress: index == count - 1 ? null : () => onMove(1),
            size: 32,
            iconSize: AppIconSizes.xs,
          ),
          AppIconButton(
            icon: FLucideIcons.x,
            tooltip: l10n.executionDailyFocusRemove,
            onPress: onRemove,
            size: 32,
            iconSize: AppIconSizes.xs,
          ),
        ],
      ),
    );
  }
}
