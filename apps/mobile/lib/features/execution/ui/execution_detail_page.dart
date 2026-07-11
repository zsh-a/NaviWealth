import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

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
import 'execution_widgets.dart';

class ExecutionActionDetailPage extends ConsumerWidget {
  const ExecutionActionDetailPage({super.key, required this.actionId});

  final String actionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actionAsync = ref.watch(executionActionDetailProvider(actionId));
    final currentAction = actionAsync.asData?.value;
    return ObjectDetailScaffold(
      title: l10n.executionActionField,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.messageSquareText),
          semanticsLabel: l10n.executionCreateProgressTitle,
          onPress: () {
            showExecutionProgressSheet(context: context, action: currentAction);
          },
        ),
        if (currentAction != null)
          FHeaderAction(
            icon: const Icon(FLucideIcons.pencil),
            semanticsLabel: l10n.executionEditActionTitle,
            onPress: () => showExecutionActionSheet(
              context: context,
              action: currentAction,
            ),
          ),
      ],
      child: actionAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => ExecutionStateView(
          icon: FLucideIcons.circleX,
          title: l10n.commonError,
          message: userSafeErrorMessage(context, error),
        ),
        data: (action) {
          if (action == null) {
            return _DetailMissingState(
              title: l10n.executionDetailMissingTitle,
              message: l10n.executionDetailMissingBody,
            );
          }
          return _ActionDetailBody(action: action);
        },
      ),
    );
  }
}

class ExecutionCommitmentDetailPage extends ConsumerWidget {
  const ExecutionCommitmentDetailPage({super.key, required this.commitmentId});

  final String commitmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final commitmentAsync = ref.watch(
      executionCommitmentDetailProvider(commitmentId),
    );
    final currentCommitment = commitmentAsync.asData?.value;
    return ObjectDetailScaffold(
      title: l10n.executionCommitmentField,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.messageSquareText),
          semanticsLabel: l10n.executionCreateProgressTitle,
          onPress: () {
            showExecutionProgressSheet(
              context: context,
              projectId: currentCommitment?.projectId,
              commitmentId: currentCommitment?.id ?? commitmentId,
            );
          },
        ),
        if (currentCommitment != null)
          FHeaderAction(
            icon: const Icon(FLucideIcons.pencil),
            semanticsLabel: l10n.executionEditCommitmentTitle,
            onPress: () => showExecutionCommitmentSheet(
              context: context,
              commitment: currentCommitment,
            ),
          ),
      ],
      child: commitmentAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => ExecutionStateView(
          icon: FLucideIcons.circleX,
          title: l10n.commonError,
          message: userSafeErrorMessage(context, error),
        ),
        data: (commitment) {
          if (commitment == null) {
            return _DetailMissingState(
              title: l10n.executionDetailMissingTitle,
              message: l10n.executionDetailMissingBody,
            );
          }
          return _CommitmentDetailBody(commitment: commitment);
        },
      ),
    );
  }
}

class _ActionDetailBody extends ConsumerWidget {
  const _ActionDetailBody({required this.action});

  final ExecutionAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final relations = ref.watch(executionActionRelationsProvider).value;
    final progressAsync = ref.watch(
      executionProgressForActionProvider(action.id),
    );
    return ListView(
      padding: _detailPadding(context),
      children: [
        ExecutionActionCardController(
          action: action,
          showActions: false,
          projectLabel: relations?.projectLabel(action.projectId),
          commitmentLabel: relations?.commitmentLabel(action.commitmentId),
          onEdit: () =>
              showExecutionActionSheet(context: context, action: action),
          onRecordProgress: () =>
              showExecutionProgressSheet(context: context, action: action),
          blockedProgressNote: l10n.executionProgressBlockedDefault,
          doneProgressNote: l10n.executionProgressDoneDefault,
          droppedProgressNote: l10n.executionProgressDroppedDefault,
        ),
        const SizedBox(height: AppSpacing.s20),
        _ProgressTimeline(
          entries: progressAsync,
          title: l10n.executionTimelineSection,
          emptyMessage: l10n.executionReviewEmptyBody,
          relationLabels: relations,
        ),
      ],
    );
  }
}

class _CommitmentDetailBody extends ConsumerWidget {
  const _CommitmentDetailBody({required this.commitment});

  final ExecutionCommitment commitment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final relations = ref.watch(executionActionRelationsProvider).value;
    final actionsAsync = ref.watch(
      executionActionsForCommitmentProvider(commitment.id),
    );
    final progressAsync = ref.watch(
      executionProgressForCommitmentProvider(commitment.id),
    );
    final actions = actionsAsync.asData?.value ?? const <ExecutionAction>[];
    return ListView(
      padding: _detailPadding(context),
      children: [
        ExecutionCommitmentCardController(
          commitment: commitment,
          showActions: false,
          openActionCount: actions.where((action) => action.isOpen).length,
          blockedActionCount: actions
              .where((action) => action.status == ExecutionActionStatus.blocked)
              .length,
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
        ),
        const SizedBox(height: AppSpacing.s20),
        _RelatedActionsSection(
          actionsAsync: actionsAsync,
          relations: relations,
        ),
        const SizedBox(height: AppSpacing.s20),
        _ProgressTimeline(
          entries: progressAsync,
          title: l10n.executionTimelineSection,
          emptyMessage: l10n.executionReviewEmptyBody,
          relationLabels: relations,
        ),
      ],
    );
  }
}

class _RelatedActionsSection extends ConsumerWidget {
  const _RelatedActionsSection({
    required this.actionsAsync,
    required this.relations,
  });

  final AsyncValue<List<ExecutionAction>> actionsAsync;
  final ExecutionRelations? relations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return actionsAsync.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (error, _) => ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: userSafeErrorMessage(context, error),
      ),
      data: (actions) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExecutionSectionHeader(
              title: l10n.executionRelatedActionsSection,
              count: actions.length,
              icon: FLucideIcons.listTodo,
            ),
            const SizedBox(height: AppSpacing.s8),
            if (actions.isEmpty)
              ExecutionStateView(
                icon: FLucideIcons.listTodo,
                title: l10n.executionTodayFilteredEmptyTitle,
                message: l10n.executionCommitmentsEmptyBody,
              )
            else
              for (final action in actions) ...[
                ExecutionActionCardController(
                  action: action,
                  projectLabel: relations?.projectLabel(action.projectId),
                  commitmentLabel: relations?.commitmentLabel(
                    action.commitmentId,
                  ),
                  onOpen: () => context.push(ExecutionRoutes.action(action.id)),
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
                const SizedBox(height: AppSpacing.s8),
              ],
          ],
        );
      },
    );
  }
}

class _ProgressTimeline extends StatelessWidget {
  const _ProgressTimeline({
    required this.entries,
    required this.title,
    required this.emptyMessage,
    required this.relationLabels,
  });

  final AsyncValue<List<ExecutionProgressEntry>> entries;
  final String title;
  final String emptyMessage;
  final ExecutionRelations? relationLabels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return entries.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (error, _) => ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: userSafeErrorMessage(context, error),
      ),
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExecutionSectionHeader(
            title: title,
            count: items.length,
            icon: FLucideIcons.history,
          ),
          const SizedBox(height: AppSpacing.s8),
          if (items.isEmpty)
            ExecutionStateView(
              icon: FLucideIcons.messageSquareText,
              title: l10n.executionReviewEmptyTitle,
              message: emptyMessage,
            )
          else
            for (final entry in items) ...[
              ExecutionProgressCard(
                entry: entry,
                actionLabel: relationLabels?.actionLabel(entry.actionId),
                projectLabel: relationLabels?.projectLabel(entry.projectId),
                commitmentLabel: relationLabels?.commitmentLabel(
                  entry.commitmentId,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
        ],
      ),
    );
  }
}

class _DetailMissingState extends StatelessWidget {
  const _DetailMissingState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _detailPadding(context),
      children: [
        ExecutionStateView(
          icon: FLucideIcons.searchX,
          title: title,
          message: message,
        ),
      ],
    );
  }
}

EdgeInsets _detailPadding(BuildContext context) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(
    AppSpacing.s16,
    AppSpacing.s16,
    AppSpacing.s16,
    bottom + AppSpacing.s24,
  );
}
