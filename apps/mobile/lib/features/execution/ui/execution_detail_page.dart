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
import 'execution_lifecycle_card_controller.dart';
import 'execution_plan_sheet.dart';
import 'execution_progress_sheet.dart';
import 'execution_source_route.dart';
import 'execution_widgets.dart';

class ExecutionActionDetailPage extends ConsumerWidget {
  const ExecutionActionDetailPage({super.key, required this.actionId});

  final String actionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actionAsync = ref.watch(executionActionDetailProvider(actionId));
    return ObjectDetailScaffold(
      title: l10n.executionActionField,
      actions: const [],
      child: actionAsync.when(
        loading: () => AppListPageSkeleton(
          padding: _detailPadding(context),
          itemCount: 2,
          showControls: false,
        ),
        error: (error, stackTrace) => kDefaultError(
          context,
          error,
          stackTrace,
          onRetry: () =>
              ref.invalidate(executionActionDetailProvider(actionId)),
        ),
        data: (action) {
          if (action == null) {
            return _DetailMissingState(
              title: l10n.executionDetailMissingTitle,
              message: l10n.executionDetailMissingBody,
            );
          }
          return _ActionDetailBody(key: ValueKey(action.id), action: action);
        },
      ),
    );
  }
}

class ExecutionPlanDetailPage extends ConsumerWidget {
  const ExecutionPlanDetailPage({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final planAsync = ref.watch(executionPlanDetailProvider(planId));
    return ObjectDetailScaffold(
      title: l10n.executionPlanField,
      actions: const [],
      child: planAsync.when(
        loading: () => AppListPageSkeleton(
          padding: _detailPadding(context),
          itemCount: 3,
          showControls: false,
        ),
        error: (error, stackTrace) => kDefaultError(
          context,
          error,
          stackTrace,
          onRetry: () => ref.invalidate(executionPlanDetailProvider(planId)),
        ),
        data: (plan) {
          if (plan == null) {
            return _DetailMissingState(
              title: l10n.executionDetailMissingTitle,
              message: l10n.executionDetailMissingBody,
            );
          }
          return _PlanDetailBody(key: ValueKey(plan.id), plan: plan);
        },
      ),
    );
  }
}

class _PlanDetailBody extends ConsumerStatefulWidget {
  const _PlanDetailBody({super.key, required this.plan});
  final ExecutionPlan plan;
  @override
  ConsumerState<_PlanDetailBody> createState() => _PlanDetailBodyState();
}

class _PlanDetailBodyState extends ConsumerState<_PlanDetailBody> {
  int _actionLimit = 30;
  int _progressLimit = 30;
  List<ExecutionAction> _actions = const [];
  List<ExecutionProgressEntry> _progress = const [];

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final l10n = AppLocalizations.of(context);
    final relations = ref.watch(executionActionRelationsProvider).value;
    final actionKey = (id: plan.id, limit: _actionLimit);
    final progressKey = (id: plan.id, forPlan: true, limit: _progressLimit);
    final actions = ref.watch(executionPlanActionsPageProvider(actionKey));
    final progress = ref.watch(
      executionRelatedProgressPageProvider(progressKey),
    );
    final counts = ref.watch(executionPlanActionCountsProvider(plan.id));
    final progressCount = ref.watch(
      executionRelatedProgressCountProvider((id: plan.id, forPlan: true)),
    );
    if (actions.hasValue) _actions = actions.requireValue;
    if (progress.hasValue) _progress = progress.requireValue;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: _detailPadding(context),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: ExecutionPlanCardController(
                  plan: plan,
                  openActionCount: counts.value?.open,
                  blockedActionCount: counts.value?.blocked,
                  onCreateAction: () => showExecutionActionSheet(
                    context: context,
                    initialPlanId: plan.id,
                  ),
                  onEdit: () =>
                      showExecutionPlanSheet(context: context, plan: plan),
                  onRecordProgress: () => showExecutionProgressSheet(
                    context: context,
                    planId: plan.id,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s20)),
              ..._pagedSlivers<ExecutionAction>(
                context,
                title: l10n.executionRelatedActionsSection,
                icon: FLucideIcons.listTodo,
                value: actions,
                retained: _actions,
                count: counts.whenData((value) => value.total),
                emptyTitle: l10n.executionTodayFilteredEmptyTitle,
                emptyMessage: l10n.executionPlansEmptyBody,
                onRetry: () {
                  ref.invalidate(executionPlanActionsPageProvider(actionKey));
                  ref.invalidate(executionPlanActionCountsProvider(plan.id));
                },
                onMore: () => setState(() => _actionLimit += 30),
                itemBuilder: (action) => ExecutionActionCardController(
                  key: ValueKey(action.id),
                  action: action,
                  planLabel: relations?.planLabel(action.planId),
                  onOpen: () => context.push(ExecutionRoutes.action(action.id)),
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
                  doneProgressNote: l10n.executionProgressDoneDefault,
                  droppedProgressNote: l10n.executionProgressDroppedDefault,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s20)),
              ..._progressSlivers(
                context,
                value: progress,
                retained: _progress,
                count: progressCount,
                relations: relations,
                onMore: () => setState(() => _progressLimit += 30),
                onRetry: () {
                  ref.invalidate(
                    executionRelatedProgressPageProvider(progressKey),
                  );
                  ref.invalidate(
                    executionRelatedProgressCountProvider((
                      id: plan.id,
                      forPlan: true,
                    )),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionDetailBody extends ConsumerStatefulWidget {
  const _ActionDetailBody({super.key, required this.action});
  final ExecutionAction action;
  @override
  ConsumerState<_ActionDetailBody> createState() => _ActionDetailBodyState();
}

class _ActionDetailBodyState extends ConsumerState<_ActionDetailBody> {
  int _limit = 30;
  List<ExecutionProgressEntry> _progress = const [];
  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final l10n = AppLocalizations.of(context);
    final relations = ref.watch(executionActionRelationsProvider).value;
    final key = (id: action.id, forPlan: false, limit: _limit);
    final progress = ref.watch(executionRelatedProgressPageProvider(key));
    final count = ref.watch(
      executionRelatedProgressCountProvider((id: action.id, forPlan: false)),
    );
    if (progress.hasValue) _progress = progress.requireValue;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: _detailPadding(context),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: ExecutionActionCardController(
                  action: action,
                  planLabel: relations?.planLabel(action.planId),
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
                  doneProgressNote: l10n.executionProgressDoneDefault,
                  droppedProgressNote: l10n.executionProgressDroppedDefault,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s20)),
              ..._progressSlivers(
                context,
                value: progress,
                retained: _progress,
                count: count,
                relations: relations,
                onMore: () => setState(() => _limit += 30),
                onRetry: () {
                  ref.invalidate(executionRelatedProgressPageProvider(key));
                  ref.invalidate(
                    executionRelatedProgressCountProvider((
                      id: action.id,
                      forPlan: false,
                    )),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

List<Widget> _progressSlivers(
  BuildContext context, {
  required AsyncValue<List<ExecutionProgressEntry>> value,
  required List<ExecutionProgressEntry> retained,
  required AsyncValue<int> count,
  required ExecutionRelations? relations,
  required VoidCallback onMore,
  required VoidCallback onRetry,
}) {
  final l10n = AppLocalizations.of(context);
  return _pagedSlivers<ExecutionProgressEntry>(
    context,
    title: l10n.executionTimelineSection,
    icon: FLucideIcons.history,
    value: value,
    retained: retained,
    count: count,
    emptyTitle: l10n.executionReviewEmptyTitle,
    emptyMessage: l10n.executionReviewEmptyBody,
    onMore: onMore,
    onRetry: onRetry,
    itemBuilder: (entry) => ExecutionProgressCard(
      key: ValueKey(entry.id),
      entry: entry,
      actionLabel: relations?.actionLabel(entry.actionId),
      planLabel: relations?.planLabel(entry.planId),
      onEdit: () =>
          showExecutionProgressSheet(context: context, progress: entry),
      onActionOpen: entry.actionId == null
          ? null
          : () => context.push(ExecutionRoutes.action(entry.actionId!)),
      onPlanOpen: entry.planId == null
          ? null
          : () => context.push(ExecutionRoutes.plan(entry.planId!)),
    ),
  );
}

List<Widget> _pagedSlivers<T>(
  BuildContext context, {
  required String title,
  required IconData icon,
  required AsyncValue<List<T>> value,
  required List<T> retained,
  required AsyncValue<int> count,
  required String emptyTitle,
  required String emptyMessage,
  required Widget Function(T) itemBuilder,
  required VoidCallback onMore,
  required VoidCallback onRetry,
}) {
  final items = value.value ?? retained;
  final error = value.error ?? count.error;
  final stack = value.stackTrace ?? count.stackTrace ?? StackTrace.empty;
  return [
    SliverToBoxAdapter(
      child: ExecutionSectionHeader(
        title: title,
        count: count.value,
        icon: icon,
      ),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s8)),
    if (error != null)
      SliverToBoxAdapter(
        child: kDefaultError(context, error, stack, onRetry: onRetry),
      ),
    if (items.isEmpty && value.isLoading)
      const SliverToBoxAdapter(child: _DetailSectionSkeleton())
    else if (items.isEmpty && error == null)
      SliverToBoxAdapter(
        child: AppEmptyState(
          icon: icon,
          title: emptyTitle,
          message: emptyMessage,
        ),
      )
    else
      SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s8),
          child: itemBuilder(items[index]),
        ),
      ),
    if (items.isNotEmpty &&
        (count.value == null || count.value! > items.length))
      SliverToBoxAdapter(
        child: AppQuietButton(
          label: AppLocalizations.of(context).commonLoadMore,
          onPress: value.isLoading || error != null ? null : onMore,
        ),
      ),
    if (items.isNotEmpty && value.isLoading)
      const SliverToBoxAdapter(child: kDefaultLoading),
  ];
}

class _DetailSectionSkeleton extends StatelessWidget {
  const _DetailSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(width: 168, height: 18, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 196, height: 15, radius: AppRadius.sm),
              SizedBox(height: AppSpacing.s8),
              SkeletonBox(height: 11, radius: AppRadius.sm),
            ],
          ),
        ),
      ],
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
        AppEmptyState(
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
