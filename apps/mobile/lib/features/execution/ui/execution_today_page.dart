import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_action_card_controller.dart';
import 'execution_action_sheet.dart';
import 'execution_widgets.dart';

class ExecutionTodayPage extends ConsumerWidget {
  const ExecutionTodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionTodayTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.executionCreateActionTitle,
          onPress: () => showExecutionActionSheet(context: context, ref: ref),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(executionTodayActionsProvider);
          ref.invalidate(executionOpenActionsProvider);
          ref.invalidate(executionProjectsProvider);
          ref.invalidate(executionCommitmentsProvider);
          ref.invalidate(executionRecentProgressProvider);
          await ref.read(executionTodayActionsProvider.future);
        },
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actionsAsync = ref.watch(executionTodayActionsProvider);
    final openActionsAsync = ref.watch(executionOpenActionsProvider);
    final projectsAsync = ref.watch(executionProjectsProvider);
    final commitmentsAsync = ref.watch(executionCommitmentsProvider);
    final progressAsync = ref.watch(executionRecentProgressProvider);
    return actionsAsync.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: '$e',
      ),
      data: (actions) {
        final now = DateTime.now();
        final openActions = openActionsAsync.value ?? actions;
        final projects = projectsAsync.value ?? const <ExecutionProject>[];
        final commitments =
            commitmentsAsync.value ?? const <ExecutionCommitment>[];
        final recentProgress =
            progressAsync.value ?? const <ExecutionProgressEntry>[];
        final visibleActions = filteredExecutionActions(
          filter: _filter,
          todayActions: actions,
          openActions: openActions,
          now: now,
        );
        final snapshot = ExecutionOverviewSnapshot.fromLists(
          todayActions: actions,
          openActions: openActions,
          projects: projects,
          commitments: commitments,
          recentProgress: recentProgress,
          now: now,
        );
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellTabContentPadding(context),
          children: [
            ExecutionOverviewStrip(
              snapshot: snapshot,
              selectedFilter: _filter,
              onFilterChanged: (filter) => setState(() => _filter = filter),
            ),
            const SizedBox(height: AppSpacing.s16),
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
                        onPress: () => showExecutionActionSheet(
                          context: context,
                          ref: ref,
                        ),
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
              const SizedBox(height: AppSpacing.s8),
              for (final action in visibleActions) ...[
                ExecutionActionCardController(
                  action: action,
                  projectLabel: executionProjectRelationLabel(
                    projects,
                    action.projectId,
                  ),
                  commitmentLabel: executionCommitmentRelationLabel(
                    commitments,
                    action.commitmentId,
                  ),
                  onEdit: () => showExecutionActionSheet(
                    context: context,
                    ref: ref,
                    action: action,
                  ),
                  blockedProgressNote: l10n.executionProgressBlockedDefault,
                  doneProgressNote: l10n.executionProgressDoneDefault,
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
            ],
          ],
        );
      },
    );
  }
}
