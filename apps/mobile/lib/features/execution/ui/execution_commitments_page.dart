import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

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
import 'execution_lifecycle_card_controller.dart';
import 'execution_progress_sheet.dart';
import 'execution_project_sheet.dart';
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
      // One primary create; project/commitment land in overflow.
      directActionBudget: 1,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.executionCreateActionTitle,
          onPress: () => showExecutionActionSheet(context: context),
          order: 0,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.target,
          label: l10n.executionCreateCommitmentTitle,
          onPress: () => showExecutionCommitmentSheet(context: context),
          order: 10,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.folder,
          label: l10n.executionCreateProjectTitle,
          onPress: () => showExecutionProjectSheet(context: context),
          order: 20,
        ),
      ],
      child: ShellTabPause(
        routePath: ExecutionRoutes.commitments,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(executionProjectsProvider);
            ref.invalidate(executionClosedProjectsProvider);
            ref.invalidate(executionOpenActionsProvider);
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
    final actionsAsync = ref.watch(executionOpenActionsProvider);
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
    final projects = projectsAsync.value ?? const <ExecutionProject>[];
    final commitments = commitmentsAsync.value ?? const <ExecutionCommitment>[];
    final activeView = _view == _CommitmentsView.active;
    final empty =
        projects.isEmpty &&
        commitments.isEmpty &&
        (!activeView || actions.isEmpty);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellTabContentPadding(context),
      children: [
        SegmentedRow<_CommitmentsView>(
          options: _CommitmentsView.values,
          value: _view,
          labelOf: (view) => _commitmentsViewLabel(l10n, view),
          iconOf: _commitmentsViewIcon,
          onChanged: (view) => setState(() => _view = view),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (empty)
          ExecutionStateView(
            icon: activeView ? FLucideIcons.listTodo : FLucideIcons.archive,
            title: activeView
                ? l10n.executionCommitmentsEmptyTitle
                : l10n.executionCommitmentsClosedEmptyTitle,
            message: activeView
                ? l10n.executionCommitmentsEmptyBody
                : l10n.executionCommitmentsClosedEmptyBody,
            action: activeView
                ? FButton(
                    onPress: () =>
                        showExecutionCommitmentSheet(context: context),
                    child: Text(l10n.executionCreateCommitmentTitle),
                  )
                : null,
          ),
        if (!empty) ...[
          if (projects.isNotEmpty) ...[
            ExecutionSectionHeader(
              title: l10n.executionProjectsSection,
              count: projects.length,
              icon: FLucideIcons.folder,
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final project in projects) ...[
              ExecutionProjectCardController(
                project: project,
                openActionCount: _openActionCount(
                  actions,
                  projectId: project.id,
                ),
                blockedActionCount: _blockedActionCount(
                  actions,
                  projectId: project.id,
                ),
                commitmentCount: commitments
                    .where((commitment) => commitment.projectId == project.id)
                    .length,
                onCreateAction: () => showExecutionActionSheet(
                  context: context,
                  initialProjectId: project.id,
                ),
                onEdit: () => showExecutionProjectSheet(
                  context: context,
                  project: project,
                ),
                onRecordProgress: () => showExecutionProgressSheet(
                  context: context,
                  projectId: project.id,
                ),
                onOpen: () => context.push(ExecutionRoutes.project(project.id)),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            const SizedBox(height: AppSpacing.s8),
          ],
          if (commitments.isNotEmpty) ...[
            ExecutionSectionHeader(
              title: l10n.executionCommitmentsSection,
              count: commitments.length,
              icon: FLucideIcons.target,
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final commitment in commitments) ...[
              ExecutionCommitmentCardController(
                commitment: commitment,
                openActionCount: _openActionCount(
                  actions,
                  commitmentId: commitment.id,
                ),
                blockedActionCount: _blockedActionCount(
                  actions,
                  commitmentId: commitment.id,
                ),
                projectLabel:
                    relations?.projectLabel(commitment.projectId) ??
                    executionProjectRelationLabel(
                      projects,
                      commitment.projectId,
                    ),
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
              const SizedBox(height: AppSpacing.s8),
            ],
            const SizedBox(height: AppSpacing.s8),
          ],
          if (activeView && actions.isNotEmpty) ...[
            ExecutionSectionHeader(
              title: l10n.executionOpenActionsSection,
              count: actions.length,
              icon: FLucideIcons.listTodo,
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final action in actions) ...[
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
                blockedProgressNote: l10n.executionProgressBlockedDefault,
                doneProgressNote: l10n.executionProgressDoneDefault,
                droppedProgressNote: l10n.executionProgressDroppedDefault,
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
          ],
        ],
      ],
    );
  }
}

String _commitmentsViewLabel(AppLocalizations l10n, _CommitmentsView view) {
  return switch (view) {
    _CommitmentsView.active => l10n.executionLifecycleActiveView,
    _CommitmentsView.closed => l10n.executionLifecycleClosedView,
  };
}

IconData _commitmentsViewIcon(_CommitmentsView view) {
  return switch (view) {
    _CommitmentsView.active => FLucideIcons.play,
    _CommitmentsView.closed => FLucideIcons.archive,
  };
}

int _openActionCount(
  List<ExecutionAction> actions, {
  String? projectId,
  String? commitmentId,
}) {
  return actions
      .where(
        (action) =>
            (projectId == null || action.projectId == projectId) &&
            (commitmentId == null || action.commitmentId == commitmentId),
      )
      .length;
}

int _blockedActionCount(
  List<ExecutionAction> actions, {
  String? projectId,
  String? commitmentId,
}) {
  return actions
      .where(
        (action) =>
            action.status == ExecutionActionStatus.blocked &&
            (projectId == null || action.projectId == projectId) &&
            (commitmentId == null || action.commitmentId == commitmentId),
      )
      .length;
}
