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
import 'execution_commitment_sheet.dart';
import 'execution_lifecycle_card_controller.dart';
import 'execution_progress_sheet.dart';
import 'execution_project_sheet.dart';
import 'execution_widgets.dart';

enum _CommitmentsView { active, closed }

class ExecutionCommitmentsPage extends ConsumerWidget {
  const ExecutionCommitmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionCommitmentsTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.folder),
          semanticsLabel: l10n.executionCreateProjectTitle,
          onPress: () => showExecutionProjectSheet(context: context, ref: ref),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.target),
          semanticsLabel: l10n.executionCreateCommitmentTitle,
          onPress: () =>
              showExecutionCommitmentSheet(context: context, ref: ref),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.executionCreateActionTitle,
          onPress: () => showExecutionActionSheet(context: context, ref: ref),
        ),
      ],
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
      return ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: '$error',
      );
    }
    if ((actionsAsync.isLoading && !actionsAsync.hasValue) ||
        (projectsAsync.isLoading && !projectsAsync.hasValue) ||
        (commitmentsAsync.isLoading && !commitmentsAsync.hasValue)) {
      return const Center(child: FCircularProgress());
    }

    final actions = actionsAsync.value ?? const <ExecutionAction>[];
    final projects = projectsAsync.value ?? const <ExecutionProject>[];
    final commitments = commitmentsAsync.value ?? const <ExecutionCommitment>[];
    final showActions = _view == _CommitmentsView.active;
    final empty =
        projects.isEmpty &&
        commitments.isEmpty &&
        (!showActions || actions.isEmpty);

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
            icon: showActions ? FLucideIcons.listTodo : FLucideIcons.archive,
            title: showActions
                ? l10n.executionCommitmentsEmptyTitle
                : l10n.executionCommitmentsClosedEmptyTitle,
            message: showActions
                ? l10n.executionCommitmentsEmptyBody
                : l10n.executionCommitmentsClosedEmptyBody,
            action: showActions
                ? FButton(
                    onPress: () => showExecutionCommitmentSheet(
                      context: context,
                      ref: ref,
                    ),
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
                onCreateAction: () => showExecutionActionSheet(
                  context: context,
                  ref: ref,
                  initialProjectId: project.id,
                ),
                onEdit: () => showExecutionProjectSheet(
                  context: context,
                  ref: ref,
                  project: project,
                ),
                onRecordProgress: () => showExecutionProgressSheet(
                  context: context,
                  ref: ref,
                  projectId: project.id,
                ),
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
                onCreateAction: () => showExecutionActionSheet(
                  context: context,
                  ref: ref,
                  initialProjectId: commitment.projectId,
                  initialCommitmentId: commitment.id,
                ),
                onEdit: () => showExecutionCommitmentSheet(
                  context: context,
                  ref: ref,
                  commitment: commitment,
                ),
                onRecordProgress: () => showExecutionProgressSheet(
                  context: context,
                  ref: ref,
                  projectId: commitment.projectId,
                  commitmentId: commitment.id,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            const SizedBox(height: AppSpacing.s8),
          ],
          if (showActions) ...[
            ExecutionSectionHeader(
              title: l10n.executionActionsSection,
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
                onEdit: () => showExecutionActionSheet(
                  context: context,
                  ref: ref,
                  action: action,
                ),
                onRecordProgress: () => showExecutionProgressSheet(
                  context: context,
                  ref: ref,
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
