import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact_routes.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/ui/agent_results_panel.dart';
import '../../../core/lifeos/action_outcome.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as execution_agent_providers;
import '../agents/review_agent.dart' show kExecutionReviewAgentId;
import '../composition/execution_route_paths.dart';
import '../data/execution_repository.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_action_card_controller.dart';
import 'execution_action_sheet.dart';
import 'execution_delete_confirm.dart';
import 'execution_progress_sheet.dart';
import 'execution_source_route.dart';
import 'execution_widgets.dart';

class ExecutionReviewPage extends ConsumerWidget {
  const ExecutionReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionReviewTitle,
      child: ShellTabPause(
        routePath: ExecutionRoutes.review,
        child: AppRefreshIndicator(
          onRefresh: () async {
            ref.invalidate(
              execution_agent_providers.latestExecutionReviewResultsProvider,
            );
            ref.invalidate(executionRecentProgressProvider);
            ref.invalidate(executionClosedActionsProvider);
            ref.invalidate(executionReviewRelationsProvider);
            await Future.wait([
              ref.read(executionRecentProgressProvider.future),
              ref.read(executionClosedActionsProvider.future),
            ]);
          },
          child: _ReviewBody(),
        ),
      ),
    );
  }
}

class _ReviewBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progressAsync = ref.watch(executionRecentProgressProvider);
    final closedActionsAsync = ref.watch(executionClosedActionsProvider);
    final relations = ref.watch(executionReviewRelationsProvider).value;
    final outcomes = ref.watch(actionOutcomeSummariesProvider);
    final error = progressAsync.error ?? closedActionsAsync.error;
    if (error != null) {
      return AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: userSafeErrorMessage(context, error),
        retryLabel: l10n.commonRetry,
        onRetry: () {
          ref.invalidate(executionRecentProgressProvider);
          ref.invalidate(executionClosedActionsProvider);
        },
      );
    }
    if ((progressAsync.isLoading && !progressAsync.hasValue) ||
        (closedActionsAsync.isLoading && !closedActionsAsync.hasValue)) {
      return AppListPageSkeleton(padding: shellTabContentPadding(context));
    }

    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final entries = (progressAsync.value ?? const <ExecutionProgressEntry>[])
        .where((entry) => !entry.createdAt.toLocal().isBefore(cutoff))
        .toList(growable: false);
    final closedActions =
        (closedActionsAsync.value ?? const <ExecutionAction>[])
            .where((action) {
              final at = action.completedAt ?? action.createdAt;
              return !at.toLocal().isBefore(cutoff);
            })
            .toList(growable: false);
    final empty = entries.isEmpty && closedActions.isEmpty;

    final itemBuilders = <WidgetBuilder>[
      (_) => _ReviewSummary(entries: entries, closedActions: closedActions),
      (_) => const SizedBox(height: AppSpacing.s12),
      (_) => const _ExecutionReviewRunStatus(),
      (_) => const SizedBox(height: AppSpacing.s16),
      (_) => const _ExecutionReviewAgentPanel(),
      (_) => const SizedBox(height: AppSpacing.s8),
      (_) => const _ReviewNextActionsBatch(),
    ];
    if (empty) {
      itemBuilders.add(
        (_) => ExecutionStateView(
          icon: FLucideIcons.clipboardCheck,
          title: l10n.executionReviewEmptyTitle,
          message: l10n.executionReviewEmptyBody,
        ),
      );
    }
    if (entries.isNotEmpty) {
      itemBuilders
        ..add(
          (_) => ExecutionSectionHeader(
            title: l10n.executionReviewTitle,
            count: entries.length,
            icon: FLucideIcons.clipboardCheck,
          ),
        )
        ..add((_) => const SizedBox(height: AppSpacing.s8));
      for (final entry in entries) {
        itemBuilders.add(
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: ExecutionProgressCard(
              entry: entry,
              actionLabel:
                  relations?.actionLabel(entry.actionId) ??
                  _fallbackRelationLabel(entry.actionId),
              projectLabel:
                  relations?.projectLabel(entry.projectId) ??
                  _fallbackRelationLabel(entry.projectId),
              commitmentLabel:
                  relations?.commitmentLabel(entry.commitmentId) ??
                  _fallbackRelationLabel(entry.commitmentId),
              onEdit: () =>
                  showExecutionProgressSheet(context: context, progress: entry),
              onDelete: () => _deleteProgress(context, ref, entry),
              onActionOpen: entry.actionId == null
                  ? null
                  : () => context.push(ExecutionRoutes.action(entry.actionId!)),
              onProjectOpen: entry.projectId == null
                  ? null
                  : () =>
                        context.push(ExecutionRoutes.project(entry.projectId!)),
              onCommitmentOpen: entry.commitmentId == null
                  ? null
                  : () => context.push(
                      ExecutionRoutes.commitment(entry.commitmentId!),
                    ),
            ),
          ),
        );
      }
      itemBuilders.add((_) => const SizedBox(height: AppSpacing.s8));
    }
    if (closedActions.isNotEmpty) {
      itemBuilders
        ..add(
          (_) => ExecutionSectionHeader(
            title: l10n.executionClosedActionsSection,
            count: closedActions.length,
            icon: FLucideIcons.archive,
          ),
        )
        ..add((_) => const SizedBox(height: AppSpacing.s8));
      for (final action in closedActions) {
        itemBuilders.add(
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: ExecutionActionCardController(
              action: action,
              projectLabel:
                  relations?.projectLabel(action.projectId) ??
                  _fallbackRelationLabel(action.projectId),
              commitmentLabel:
                  relations?.commitmentLabel(action.commitmentId) ??
                  _fallbackRelationLabel(action.commitmentId),
              onOpen: () => context.push(ExecutionRoutes.action(action.id)),
              onSourceOpen: executionSourceOpen(context, ref, action.source),
              onEdit: () =>
                  showExecutionActionSheet(context: context, action: action),
              onRecordProgress: () =>
                  showExecutionProgressSheet(context: context, action: action),
              doneProgressNote: l10n.executionProgressDoneDefault,
              droppedProgressNote: l10n.executionProgressDroppedDefault,
              outcome: outcomes[action.id],
            ),
          ),
        );
      }
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellTabContentPadding(context),
      itemCount: itemBuilders.length,
      itemBuilder: (context, index) => itemBuilders[index](context),
    );
  }
}

class _ReviewNextActionsBatch extends ConsumerStatefulWidget {
  const _ReviewNextActionsBatch();

  @override
  ConsumerState<_ReviewNextActionsBatch> createState() =>
      _ReviewNextActionsBatchState();
}

class _ReviewNextActionsBatchState
    extends ConsumerState<_ReviewNextActionsBatch> {
  @override
  Widget build(BuildContext context) {
    final artifact = ref
        .watch(execution_agent_providers.latestExecutionReviewArtifactProvider)
        .value;
    final plan = artifact?.actions
        .where((action) => action.kind == 'proposal')
        .firstOrNull;
    if (plan == null) return const SizedBox.shrink();
    final projectIds = _stringIds(plan.payload['projects_without_next_action']);
    final commitmentIds = _stringIds(
      plan.payload['commitments_without_next_action'],
    );
    final count = projectIds.length + commitmentIds.length;
    if (count == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: FButton(
        variant: FButtonVariant.outline,
        onPress: () =>
            _review(projectIds: projectIds, commitmentIds: commitmentIds),
        child: Text(l10n.executionReviewDraftNextActions(count)),
      ),
    );
  }

  Future<void> _review({
    required List<String> projectIds,
    required List<String> commitmentIds,
  }) async {
    try {
      final owner = await ref.read(executionOwnerUserIdProvider.future);
      final repository = await ref.read(executionRepositoryProvider.future);
      final open = await repository.listOpenActions(ownerUserId: owner);
      final projectsWithAction = open
          .map((action) => action.projectId)
          .whereType<String>()
          .toSet();
      final commitmentsWithAction = open
          .map((action) => action.commitmentId)
          .whereType<String>()
          .toSet();
      final drafts = <({String id, String title, bool project})>[];
      for (final id in projectIds) {
        if (projectsWithAction.contains(id)) continue;
        final project = await repository.findProject(
          ownerUserId: owner,
          id: id,
        );
        if (project == null) continue;
        drafts.add((id: project.id, title: project.title, project: true));
      }
      for (final id in commitmentIds) {
        if (commitmentsWithAction.contains(id)) continue;
        final commitment = await repository.findCommitment(
          ownerUserId: owner,
          id: id,
        );
        if (commitment == null) continue;
        drafts.add((
          id: commitment.id,
          title: commitment.title,
          project: false,
        ));
      }
      if (!mounted) return;
      await showAppFormSheet<void>(
        context: context,
        builder: (sheetContext) => _ReviewBatchDraftSheet(
          drafts: drafts,
          onConfirm: (selected) async {
            Navigator.of(sheetContext).pop();
            await _createBatch(repository, selected);
          },
        ),
      );
    } on Object catch (error, stackTrace) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(context, error, stackTrace: stackTrace),
        );
      }
    }
  }

  Future<void> _createBatch(
    ExecutionRepository repository,
    List<({String id, String title, bool project})> drafts,
  ) async {
    if (drafts.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    try {
      for (final draft in drafts) {
        final sync = await stampExecutionSync(ref);
        await repository.upsertAction(
          ExecutionAction(
            id: kExecutionUuid.v4(),
            title: l10n.executionReviewNextActionFor(draft.title),
            priority: ExecutionPriority.high,
            projectId: draft.project ? draft.id : null,
            commitmentId: draft.project ? null : draft.id,
            createdAt: sync.updatedAt,
            sync: sync,
          ),
        );
      }
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.executionReviewCreatedNextActions(drafts.length),
        );
      }
    } on Object catch (error, stackTrace) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(context, error, stackTrace: stackTrace),
        );
      }
    }
  }
}

class _ReviewBatchDraftSheet extends StatefulWidget {
  const _ReviewBatchDraftSheet({required this.drafts, required this.onConfirm});

  final List<({String id, String title, bool project})> drafts;
  final ValueChanged<List<({String id, String title, bool project})>> onConfirm;

  @override
  State<_ReviewBatchDraftSheet> createState() => _ReviewBatchDraftSheetState();
}

class _ReviewBatchDraftSheetState extends State<_ReviewBatchDraftSheet> {
  late final Set<String> _selected = widget.drafts
      .map((draft) => '${draft.project}:${draft.id}')
      .toSet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = widget.drafts
        .where((draft) => _selected.contains('${draft.project}:${draft.id}'))
        .toList(growable: false);
    return AppSheet(
      title: l10n.executionReviewDraftNextActions(widget.drafts.length),
      footer: SafeArea(
        top: false,
        child: FButton(
          onPress: selected.isEmpty ? null : () => widget.onConfirm(selected),
          child: Text(l10n.executionReviewCreateNextActions(selected.length)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.executionReviewCreateNextActionsBody,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          for (final draft in widget.drafts)
            AppTappable(
              onPress: () => _toggle(draft),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FCheckbox(
                      value: _selected.contains('${draft.project}:${draft.id}'),
                      onChange: (_) => _toggle(draft),
                    ),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(draft.title, style: context.labelStyle),
                          const SizedBox(height: AppSpacing.s2),
                          Text(
                            l10n.executionReviewNextActionFor(draft.title),
                            style: context.captionStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggle(({String id, String title, bool project}) draft) {
    setState(() {
      final key = '${draft.project}:${draft.id}';
      if (!_selected.add(key)) _selected.remove(key);
    });
  }
}

List<String> _stringIds(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.entries, required this.closedActions});

  final List<ExecutionProgressEntry> entries;
  final List<ExecutionAction> closedActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = context.appTheme.status;
    final completed = closedActions
        .where((action) => action.status == ExecutionActionStatus.done)
        .length;
    final blockers = entries
        .where((entry) => entry.kind == ExecutionProgressKind.blocker)
        .length;
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        AppBadge(
          label: '${l10n.executionReviewCompletedMetric} $completed',
          icon: FLucideIcons.checkCheck,
          foregroundColor: status.success.fg,
        ),
        AppBadge(
          label: '${l10n.executionReviewBlockedMetric} $blockers',
          icon: FLucideIcons.octagonAlert,
          foregroundColor: blockers > 0 ? status.danger.fg : null,
        ),
        AppBadge(
          label: '${l10n.executionReviewProgressMetric} ${entries.length}',
          icon: FLucideIcons.messageSquareText,
        ),
      ],
    );
  }
}

class _ExecutionReviewRunStatus extends ConsumerStatefulWidget {
  const _ExecutionReviewRunStatus();

  @override
  ConsumerState<_ExecutionReviewRunStatus> createState() =>
      _ExecutionReviewRunStatusState();
}

class _ExecutionReviewRunStatusState
    extends ConsumerState<_ExecutionReviewRunStatus> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bundle = ref.watch(
      execution_agent_providers.latestExecutionReviewResultsProvider,
    );
    final run = bundle.value?.latestRun;
    final message = run == null
        ? l10n.executionReviewAgentNotRun
        : switch (run.status) {
            AgentRunLifecycleStatus.running => l10n.executionReviewAgentRunning,
            AgentRunLifecycleStatus.failed => l10n.executionReviewAgentFailed,
            AgentRunLifecycleStatus.ready ||
            AgentRunLifecycleStatus.noFinding =>
              l10n.executionReviewAgentLastRun(
                executionDate(context, run.finishedAt ?? run.startedAt),
              ),
          };
    return AppStatusBanner(
      compact: true,
      kind: run?.status == AgentRunLifecycleStatus.failed
          ? AppStatusKind.warning
          : AppStatusKind.info,
      icon: FLucideIcons.bot,
      message: message,
    );
  }
}

class _ExecutionReviewAgentPanel extends ConsumerStatefulWidget {
  const _ExecutionReviewAgentPanel();

  @override
  ConsumerState<_ExecutionReviewAgentPanel> createState() =>
      _ExecutionReviewAgentPanelState();
}

class _ExecutionReviewAgentPanelState
    extends ConsumerState<_ExecutionReviewAgentPanel> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(
      execution_agent_providers.latestExecutionReviewResultsProvider,
    );
    // Signal-first Review surface: quiet while loading, CTA when empty.
    return AgentResultsPanel(
      resultsAsync: resultsAsync,
      showPlaceholderStates: false,
      onReload: () => ref.invalidate(
        execution_agent_providers.latestExecutionReviewResultsProvider,
      ),
      onOpen: (artifact) =>
          context.push(AgentArtifactRoutes.detail(artifact.id)),
      onRunAgain: (_) => _retryExecutionReview(ref),
      onGenerate: _running ? null : _runReview,
      generating: _running,
    );
  }

  Future<void> _runReview() async {
    setState(() => _running = true);
    try {
      await _retryExecutionReview(ref);
    } catch (error, stackTrace) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(context, error, stackTrace: stackTrace),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

Future<void> _retryExecutionReview(WidgetRef ref) async {
  final controller = await ref.read(agentRunControllerProvider.future);
  await controller.runOnceById(kExecutionReviewAgentId);
  ref.invalidate(
    execution_agent_providers.latestExecutionReviewResultsProvider,
  );
}

String? _fallbackRelationLabel(String? id) {
  return id == null || id.isEmpty ? null : id;
}

Future<void> _deleteProgress(
  BuildContext context,
  WidgetRef ref,
  ExecutionProgressEntry entry,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await confirmExecutionDelete(
    context: context,
    item: _progressDeleteLabel(l10n, entry),
  );
  if (!confirmed || !context.mounted) return;

  final repo = await ref.read(executionRepositoryProvider.future);
  final sync = await stampExecutionSync(ref);
  await repo.softDeleteProgress(progress: entry, sync: sync);
}

String _progressDeleteLabel(
  AppLocalizations l10n,
  ExecutionProgressEntry entry,
) {
  final note = entry.note.trim();
  if (note.isEmpty) {
    return executionProgressKindLabel(l10n, entry.kind);
  }
  if (note.length <= 36) return note;
  return '${note.substring(0, 36)}...';
}
