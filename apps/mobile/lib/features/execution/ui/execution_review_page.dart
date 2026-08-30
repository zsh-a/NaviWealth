import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/attention/attention_item.dart';
import '../../../core/ai/attention/ui/attention_group.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/lifeos/action_outcome.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as execution_agent_providers;
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

final _executionAttentionProvider =
    Provider.autoDispose<AsyncValue<_ExecutionAttentionSnapshot>>((ref) {
      final actions = ref.watch(executionOpenActionsProvider);
      final plans = ref.watch(executionPlansProvider);
      if (actions.hasError && !actions.hasValue) {
        return AsyncValue.error(
          actions.error!,
          actions.stackTrace ?? StackTrace.current,
        );
      }
      if (plans.hasError && !plans.hasValue) {
        return AsyncValue.error(
          plans.error!,
          plans.stackTrace ?? StackTrace.current,
        );
      }
      if ((actions.isLoading && !actions.hasValue) ||
          (plans.isLoading && !plans.hasValue)) {
        return const AsyncValue.loading();
      }
      return AsyncValue.data(
        _ExecutionAttentionSnapshot.build(
          actions: actions.value ?? const <ExecutionAction>[],
          plans: plans.value ?? const <ExecutionPlan>[],
          now: DateTime.now(),
        ),
      );
    });

class _ExecutionAttentionSnapshot {
  const _ExecutionAttentionSnapshot({
    required this.actions,
    required this.targets,
  });

  factory _ExecutionAttentionSnapshot.build({
    required List<ExecutionAction> actions,
    required List<ExecutionPlan> plans,
    required DateTime now,
  }) {
    final actionItems = <_ExecutionActionAttention>[];
    for (final action in actions) {
      final blocked = action.status == ExecutionActionStatus.blocked;
      final due = action.isDue(now);
      final stalled =
          action.status == ExecutionActionStatus.doing &&
          now.toUtc().difference(action.sync.updatedAt.toUtc()).inDays >= 7;
      if (blocked || due || stalled) {
        actionItems.add(
          _ExecutionActionAttention(
            action: action,
            blocked: blocked,
            due: due,
            stalled: stalled,
          ),
        );
      }
    }
    actionItems.sort((left, right) {
      final leftRank = left.blocked
          ? 0
          : left.due
          ? 1
          : 2;
      final rightRank = right.blocked
          ? 0
          : right.due
          ? 1
          : 2;
      return leftRank.compareTo(rightRank);
    });

    final planIdsWithActions = actions
        .map((action) => action.planId)
        .whereType<String>()
        .toSet();
    final targetItems = <_ExecutionTargetAttention>[
      for (final plan in plans)
        if (!planIdsWithActions.contains(plan.id) ||
            _isTargetOverdue(plan.targetDate, now))
          _ExecutionTargetAttention(
            plan,
            missingNextAction: !planIdsWithActions.contains(plan.id),
            overdue: _isTargetOverdue(plan.targetDate, now),
          ),
    ];
    targetItems.sort((left, right) {
      final leftRank = left.overdue ? 0 : 1;
      final rightRank = right.overdue ? 0 : 1;
      return leftRank.compareTo(rightRank);
    });
    return _ExecutionAttentionSnapshot(
      actions: List.unmodifiable(actionItems),
      targets: List.unmodifiable(targetItems),
    );
  }

  final List<_ExecutionActionAttention> actions;
  final List<_ExecutionTargetAttention> targets;

  int get count => actions.length + targets.length;

  List<String> get plansWithoutNextAction => targets
      .where((item) => item.missingNextAction)
      .map((item) => item.plan.id)
      .toList(growable: false);
}

class _ExecutionActionAttention {
  const _ExecutionActionAttention({
    required this.action,
    required this.blocked,
    required this.due,
    required this.stalled,
  });

  final ExecutionAction action;
  final bool blocked;
  final bool due;
  final bool stalled;
}

class _ExecutionTargetAttention {
  const _ExecutionTargetAttention(
    this.plan, {
    required this.missingNextAction,
    required this.overdue,
  });

  final ExecutionPlan plan;
  final bool missingNextAction;
  final bool overdue;

  String get id => plan.id;
  String get title => plan.title;
  String get description => plan.description;
  DateTime? get targetDate => plan.targetDate;
  String get route => ExecutionRoutes.plan(plan.id);
}

bool _isTargetOverdue(DateTime? target, DateTime now) =>
    target != null && !target.toUtc().isAfter(now.toUtc());

class ExecutionReviewPage extends ConsumerWidget {
  const ExecutionReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Always pushed from the Today greeting header (never a tab root), so
    // render as an object-detail page: the standard back arrow comes from
    // appSubPageHeader via ObjectDetailScaffold.
    return ObjectDetailScaffold(
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
            ref.invalidate(executionOpenActionsProvider);
            ref.invalidate(executionPlansProvider);
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

class _ReviewBody extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends ConsumerState<_ReviewBody> {
  bool _showWeekResults = false;
  bool _showReviewDetails = false;

  @override
  Widget build(BuildContext context) {
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
    final recentEntries =
        (progressAsync.value ?? const <ExecutionProgressEntry>[])
            .where((entry) => !entry.createdAt.toLocal().isBefore(cutoff))
            .toList(growable: false);
    final closedActions =
        (closedActionsAsync.value ?? const <ExecutionAction>[])
            .where((action) {
              final at = action.completedAt ?? action.createdAt;
              return !at.toLocal().isBefore(cutoff);
            })
            .toList(growable: false);
    // Completing or dropping an Action also writes a terminal progress row.
    // Prefer the closed Action card because it retains the source outcome and
    // full lifecycle context; keep non-terminal progress as the compact log.
    final closedActionIds = closedActions.map((action) => action.id).toSet();
    final entries = recentEntries
        .where(
          (entry) =>
              entry.actionId == null ||
              !closedActionIds.contains(entry.actionId) ||
              (entry.kind != ExecutionProgressKind.completion &&
                  entry.kind != ExecutionProgressKind.dropped),
        )
        .toList(growable: false);
    final empty = entries.isEmpty && closedActions.isEmpty;

    final itemBuilders = <WidgetBuilder>[
      (_) => const _ExecutionAttentionSection(),
      (_) => const SizedBox(height: AppSpacing.s20),
      (_) => ExecutionSectionHeader(
        title: l10n.executionReviewWeekResultsTitle,
        count: entries.length + closedActions.length,
        icon: FLucideIcons.chartNoAxesColumnIncreasing,
      ),
      (_) => const SizedBox(height: AppSpacing.s8),
      (_) => _ReviewSummary(entries: entries, closedActions: closedActions),
      (_) => const SizedBox(height: AppSpacing.s12),
      (_) => _ReviewDisclosure(
        icon: FLucideIcons.history,
        title: l10n.executionReviewRecentActivity(
          entries.length + closedActions.length,
        ),
        expanded: _showWeekResults,
        onTap: () => setState(() => _showWeekResults = !_showWeekResults),
      ),
      (_) => const SizedBox(height: AppSpacing.s12),
    ];
    if (_showWeekResults && empty) {
      itemBuilders.add(
        (_) => AppEmptyState(
          icon: FLucideIcons.clipboardCheck,
          title: l10n.executionReviewEmptyTitle,
          message: l10n.executionReviewEmptyBody,
        ),
      );
    }
    if (_showWeekResults && entries.isNotEmpty) {
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
              planLabel:
                  relations?.planLabel(entry.planId) ??
                  _fallbackRelationLabel(entry.planId),
              onEdit: () =>
                  showExecutionProgressSheet(context: context, progress: entry),
              onDelete: () => _deleteProgress(context, ref, entry),
              onActionOpen: entry.actionId == null
                  ? null
                  : () => context.push(ExecutionRoutes.action(entry.actionId!)),
              onPlanOpen: entry.planId == null
                  ? null
                  : () => context.push(ExecutionRoutes.plan(entry.planId!)),
            ),
          ),
        );
      }
      itemBuilders.add((_) => const SizedBox(height: AppSpacing.s8));
    }
    if (_showWeekResults && closedActions.isNotEmpty) {
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
              planLabel:
                  relations?.planLabel(action.planId) ??
                  _fallbackRelationLabel(action.planId),
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
    itemBuilders
      ..add((_) => const SizedBox(height: AppSpacing.s8))
      ..add(
        (_) => _ReviewDisclosure(
          icon: FLucideIcons.info,
          title: l10n.executionReviewDetailsTitle,
          subtitle: l10n.executionReviewDetailsSubtitle,
          expanded: _showReviewDetails,
          onTap: () => setState(() => _showReviewDetails = !_showReviewDetails),
        ),
      );
    if (_showReviewDetails) {
      itemBuilders
        ..add((_) => const SizedBox(height: AppSpacing.s8))
        ..add((_) => const _ExecutionReviewRunStatus());
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellTabContentPadding(context),
      itemCount: itemBuilders.length,
      itemBuilder: (context, index) => itemBuilders[index](context),
    );
  }
}

class _ExecutionAttentionSection extends ConsumerWidget {
  const _ExecutionAttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(_executionAttentionProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => AppEmptyState.inline(
        icon: FLucideIcons.triangleAlert,
        title: userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'load execution attention',
        ),
        tone: AppEmptyStateTone.error,
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(_executionAttentionProvider),
      ),
      data: (snapshot) {
        if (snapshot.count == 0) return const SizedBox.shrink();
        final items = <AttentionItem>[
          for (final entry in snapshot.actions)
            _actionAttentionItem(context, l10n, entry),
          for (final entry in snapshot.targets)
            _targetAttentionItem(context, l10n, entry),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AttentionGroup(
              title: l10n.executionReviewNeedsAttentionTitle,
              items: items,
              onOpen: (item) => showAttentionItemSheet(
                context: context,
                item: item,
                evidenceTitle: l10n.agentResultEvidenceSection,
                actionLabel: l10n.agentResultOpenRelatedPage,
                onAction: () => context.push(item.route!),
              ),
            ),
            if (snapshot.plansWithoutNextAction.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s10),
              _ReviewNextActionsBatch(planIds: snapshot.plansWithoutNextAction),
            ],
          ],
        );
      },
    );
  }

  AttentionItem _actionAttentionItem(
    BuildContext context,
    AppLocalizations l10n,
    _ExecutionActionAttention entry,
  ) {
    final action = entry.action;
    final reasons = <String>[
      if (entry.blocked) l10n.executionAgentReviewInsightBlockedTitle,
      if (entry.due) l10n.executionAgentReviewInsightDueTitle,
      if (entry.stalled) l10n.executionAgentReviewInsightStalledTitle,
    ];
    return AttentionItem(
      id: 'execution:action:${action.id}',
      domain: DomainScope.execution,
      headline: action.title,
      rationale: reasons.join(' · '),
      severity: entry.blocked || entry.stalled
          ? AttentionItemSeverity.warning
          : AttentionItemSeverity.attention,
      facts: <AttentionFact>[
        AttentionFact(
          label: l10n.executionStatusField,
          value: executionStatusLabel(l10n, action.status),
        ),
        if (action.dueAt != null)
          AttentionFact(
            label: l10n.executionDueAtField,
            value: executionDate(context, action.dueAt!),
          ),
      ],
      evidence: <AttentionEvidence>[
        AttentionEvidence(
          label: l10n.executionActionField,
          detail: action.note.trim().isEmpty ? null : action.note.trim(),
          route: ExecutionRoutes.action(action.id),
        ),
      ],
      route: ExecutionRoutes.action(action.id),
      observedAt: action.sync.updatedAt,
    );
  }

  AttentionItem _targetAttentionItem(
    BuildContext context,
    AppLocalizations l10n,
    _ExecutionTargetAttention entry,
  ) {
    final reasons = <String>[
      if (entry.overdue) l10n.executionAgentReviewInsightOverdueTargetsTitle,
      if (entry.missingNextAction)
        l10n.executionAgentReviewInsightNoNextActionTitle,
    ];
    return AttentionItem(
      id: 'execution:plan:${entry.id}',
      domain: DomainScope.execution,
      headline: entry.title,
      rationale: reasons.join(' · '),
      severity: entry.overdue
          ? AttentionItemSeverity.warning
          : AttentionItemSeverity.attention,
      facts: <AttentionFact>[
        AttentionFact(
          label: l10n.executionPlanField,
          value: entry.missingNextAction
              ? l10n.executionAgentReviewInsightNoNextActionTitle
              : l10n.executionAgentReviewInsightOverdueTargetsTitle,
        ),
        if (entry.targetDate != null)
          AttentionFact(
            label: l10n.executionTargetDateField,
            value: executionDate(context, entry.targetDate!),
          ),
      ],
      evidence: <AttentionEvidence>[
        AttentionEvidence(
          label: l10n.executionPlanField,
          detail: entry.description.trim().isEmpty
              ? null
              : entry.description.trim(),
          route: entry.route,
        ),
      ],
      route: entry.route,
      observedAt: entry.plan.sync.updatedAt,
    );
  }
}

class _ReviewDisclosure extends StatelessWidget {
  const _ReviewDisclosure({
    required this.icon,
    required this.title,
    required this.expanded,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      expanded: expanded,
      child: AppGroupedSurface(
        padding: EdgeInsets.zero,
        child: AppTappable(
          onPress: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s14,
              vertical: AppSpacing.s12,
            ),
            child: Row(
              children: [
                Icon(icon, size: AppIconSizes.sm, color: colors.primary),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.labelStyle),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.s2),
                        Text(subtitle!, style: context.captionStyle),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.sm,
                  color: colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewNextActionsBatch extends ConsumerStatefulWidget {
  const _ReviewNextActionsBatch({required this.planIds});

  final List<String> planIds;

  @override
  ConsumerState<_ReviewNextActionsBatch> createState() =>
      _ReviewNextActionsBatchState();
}

class _ReviewNextActionsBatchState
    extends ConsumerState<_ReviewNextActionsBatch> {
  @override
  Widget build(BuildContext context) {
    final count = widget.planIds.length;
    if (count == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: FButton(
        onPress: () => _review(planIds: widget.planIds),
        child: Text(l10n.executionReviewDraftNextActions(count)),
      ),
    );
  }

  Future<void> _review({required List<String> planIds}) async {
    try {
      final owner = await ref.read(executionOwnerUserIdProvider.future);
      final repository = await ref.read(executionRepositoryProvider.future);
      final open = await repository.listOpenActions(ownerUserId: owner);
      final plansWithAction = open
          .map((action) => action.planId)
          .whereType<String>()
          .toSet();
      final drafts = <({String id, String title})>[];
      for (final id in planIds) {
        if (plansWithAction.contains(id)) continue;
        final plan = await repository.findPlan(ownerUserId: owner, id: id);
        if (plan == null) continue;
        drafts.add((id: plan.id, title: plan.title));
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
    List<({String id, String title})> drafts,
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
            planId: draft.id,
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

  final List<({String id, String title})> drafts;
  final ValueChanged<List<({String id, String title})>> onConfirm;

  @override
  State<_ReviewBatchDraftSheet> createState() => _ReviewBatchDraftSheetState();
}

class _ReviewBatchDraftSheetState extends State<_ReviewBatchDraftSheet> {
  late final Set<String> _selected = widget.drafts
      .map((draft) => draft.id)
      .toSet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = widget.drafts
        .where((draft) => _selected.contains(draft.id))
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
                      value: _selected.contains(draft.id),
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

  void _toggle(({String id, String title}) draft) {
    setState(() {
      if (!_selected.add(draft.id)) _selected.remove(draft.id);
    });
  }
}

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
