import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_action_card_controller.dart';
import 'execution_action_sheet.dart';
import 'execution_commitment_sheet.dart';
import 'execution_create_sheet.dart';
import 'execution_lifecycle_card_controller.dart';
import 'execution_progress_sheet.dart';
import 'execution_project_sheet.dart';
import 'execution_search_sheet.dart';
import 'execution_source_route.dart';
import 'execution_widgets.dart';

enum _CommitmentsView { active, closed }

class ExecutionCommitmentsPage extends ConsumerWidget {
  const ExecutionCommitmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionCommitmentsTitle,
      directActionBudget: 1,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.executionCreatePlanTitle,
          onPress: () => showExecutionCreateSheet(context),
          order: -10,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.search,
          label: l10n.executionSearchTitle,
          onPress: () => showExecutionSearchSheet(context: context),
          order: 10,
        ),
      ],
      child: ShellTabPause(
        routePath: ExecutionRoutes.commitments,
        child: AppRefreshIndicator(
          onRefresh: () async {
            ref.invalidate(executionProjectsProvider);
            ref.invalidate(executionClosedProjectsProvider);
            ref.invalidate(executionOpenActionsProvider);
            ref.invalidate(executionClosedActionsProvider);
            ref.invalidate(executionCommitmentsProvider);
            ref.invalidate(executionClosedCommitmentsProvider);
            ref.invalidate(executionRecentProgressProvider);
            ref.invalidate(executionActionRelationsProvider);
            await ref.read(executionOpenActionsProvider.future);
          },
          child: _CommitmentsBody(),
        ),
      ),
    );
  }
}

class _CommitmentsBody extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CommitmentsBody> createState() => _CommitmentsBodyState();
}

class _CommitmentsBodyState extends ConsumerState<_CommitmentsBody> {
  _CommitmentsView _view = _CommitmentsView.active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(
      _view == _CommitmentsView.active
          ? executionProjectsProvider
          : executionClosedProjectsProvider,
    );
    final actionsAsync = ref.watch(
      _view == _CommitmentsView.active
          ? executionOpenActionsProvider
          : executionClosedActionsProvider,
    );
    final commitmentsAsync = ref.watch(
      _view == _CommitmentsView.active
          ? executionCommitmentsProvider
          : executionClosedCommitmentsProvider,
    );
    final relations = ref.watch(executionActionRelationsProvider).value;
    final error =
        actionsAsync.error ?? projectsAsync.error ?? commitmentsAsync.error;
    if (error != null) {
      return AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: userSafeErrorMessage(context, error),
        retryLabel: l10n.commonRetry,
        onRetry: () {
          ref.invalidate(executionProjectsProvider);
          ref.invalidate(executionClosedProjectsProvider);
          ref.invalidate(executionOpenActionsProvider);
          ref.invalidate(executionClosedActionsProvider);
          ref.invalidate(executionCommitmentsProvider);
          ref.invalidate(executionClosedCommitmentsProvider);
        },
      );
    }
    if ((actionsAsync.isLoading && !actionsAsync.hasValue) ||
        (projectsAsync.isLoading && !projectsAsync.hasValue) ||
        (commitmentsAsync.isLoading && !commitmentsAsync.hasValue)) {
      return AppListPageSkeleton(padding: shellTabContentPadding(context));
    }

    final actions = actionsAsync.value ?? const <ExecutionAction>[];
    final standaloneActions = actions
        .where(
          (action) => action.projectId == null && action.commitmentId == null,
        )
        .toList(growable: false);
    final projects = projectsAsync.value ?? const <ExecutionProject>[];
    final commitments = commitmentsAsync.value ?? const <ExecutionCommitment>[];
    final activeView = _view == _CommitmentsView.active;
    final empty = projects.isEmpty && commitments.isEmpty && actions.isEmpty;
    final actionCountByProject = <String, int>{};
    final blockedCountByProject = <String, int>{};
    final actionCountByCommitment = <String, int>{};
    final blockedCountByCommitment = <String, int>{};
    final commitmentCountByProject = <String, int>{};
    for (final action in actions) {
      if (action.projectId case final projectId?) {
        actionCountByProject.update(
          projectId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (action.status == ExecutionActionStatus.blocked) {
          blockedCountByProject.update(
            projectId,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
      if (action.commitmentId case final commitmentId?) {
        actionCountByCommitment.update(
          commitmentId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (action.status == ExecutionActionStatus.blocked) {
          blockedCountByCommitment.update(
            commitmentId,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }
    for (final commitment in commitments) {
      if (commitment.projectId case final projectId?) {
        commitmentCountByProject.update(
          projectId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final itemBuilders = <WidgetBuilder>[
      if (!activeView) ...[
        (_) => AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: InlineLinkRow(
            icon: FLucideIcons.arrowLeft,
            label: l10n.executionActiveWorkEntry,
            onTap: () => setState(() => _view = _CommitmentsView.active),
          ),
        ),
        (_) => const SizedBox(height: AppSpacing.s16),
      ],
    ];
    if (empty) {
      itemBuilders.add(
        (_) => ExecutionStateView(
          icon: activeView ? FLucideIcons.listTodo : FLucideIcons.archive,
          title: activeView
              ? l10n.executionCommitmentsEmptyTitle
              : l10n.executionCommitmentsClosedEmptyTitle,
          message: activeView
              ? l10n.executionCommitmentsEmptyBody
              : l10n.executionCommitmentsClosedEmptyBody,
          action: activeView
              ? FButton(
                  onPress: () => showExecutionActionSheet(context: context),
                  child: Text(l10n.executionCreateActionTitle),
                )
              : null,
        ),
      );
    }
    if (standaloneActions.isNotEmpty) {
      itemBuilders
        ..add(
          (_) => ExecutionSectionHeader(
            title: activeView
                ? l10n.executionInboxSection
                : l10n.executionClosedActionsSection,
            count: standaloneActions.length,
            icon: activeView ? FLucideIcons.inbox : FLucideIcons.archive,
          ),
        )
        ..add((_) => const SizedBox(height: AppSpacing.s8));
      for (final action in standaloneActions) {
        itemBuilders.add(
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: ExecutionActionCardController(
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
              onRecordProgress: () =>
                  showExecutionProgressSheet(context: context, action: action),
              doneProgressNote: l10n.executionProgressDoneDefault,
              droppedProgressNote: l10n.executionProgressDroppedDefault,
            ),
          ),
        );
      }
      itemBuilders.add((_) => const SizedBox(height: AppSpacing.s8));
    }
    if (projects.isNotEmpty || commitments.isNotEmpty) {
      itemBuilders
        ..add(
          (_) => ExecutionSectionHeader(
            title: l10n.executionProjectsSection,
            count: projects.length + commitments.length,
            icon: FLucideIcons.layers,
          ),
        )
        ..add((_) => const SizedBox(height: AppSpacing.s8));
    }
    if (projects.isNotEmpty) {
      for (final project in projects) {
        itemBuilders.add(
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: ExecutionProjectCardController(
              project: project,
              openActionCount: actionCountByProject[project.id] ?? 0,
              blockedActionCount: blockedCountByProject[project.id] ?? 0,
              commitmentCount: commitmentCountByProject[project.id] ?? 0,
              showTypeLabel: true,
              onCreateAction: () => showExecutionActionSheet(
                context: context,
                initialProjectId: project.id,
              ),
              onEdit: () =>
                  showExecutionProjectSheet(context: context, project: project),
              onRecordProgress: () => showExecutionProgressSheet(
                context: context,
                projectId: project.id,
              ),
              onOpen: () => context.push(ExecutionRoutes.project(project.id)),
            ),
          ),
        );
      }
    }
    if (commitments.isNotEmpty) {
      for (final commitment in commitments) {
        itemBuilders.add(
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: ExecutionCommitmentCardController(
              commitment: commitment,
              openActionCount: actionCountByCommitment[commitment.id] ?? 0,
              blockedActionCount: blockedCountByCommitment[commitment.id] ?? 0,
              showTypeLabel: true,
              projectLabel:
                  relations?.projectLabel(commitment.projectId) ??
                  executionProjectRelationLabel(projects, commitment.projectId),
              onCreateAction: () => showExecutionActionSheet(
                context: context,
                initialProjectId: commitment.projectId,
                initialCommitmentId: commitment.id,
              ),
              onEdit: () => showExecutionCommitmentSheet(
                context: context,
                commitment: commitment,
              ),
              onRecordProgress: () => showExecutionProgressSheet(
                context: context,
                projectId: commitment.projectId,
                commitmentId: commitment.id,
              ),
              onOpen: () =>
                  context.push(ExecutionRoutes.commitment(commitment.id)),
            ),
          ),
        );
      }
    }
    if (activeView) {
      itemBuilders
        ..add((_) => const SizedBox(height: AppSpacing.s12))
        ..add(
          (_) => AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: InlineLinkRow(
              icon: FLucideIcons.archive,
              label: l10n.executionClosedWorkEntry,
              onTap: () => setState(() => _view = _CommitmentsView.closed),
            ),
          ),
        );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellTabContentPadding(context),
      itemCount: itemBuilders.length,
      itemBuilder: (context, index) => itemBuilders[index](context),
    );
  }
}
