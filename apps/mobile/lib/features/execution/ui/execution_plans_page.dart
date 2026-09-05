import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/master_detail_layout.dart';
import '../../../core/shell/selection_query.dart';
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
import 'execution_create_sheet.dart';
import 'execution_detail_page.dart';
import 'execution_lifecycle_card_controller.dart';
import 'execution_plan_sheet.dart';
import 'execution_progress_sheet.dart';
import 'execution_search_sheet.dart';
import 'execution_source_route.dart';
import 'execution_widgets.dart';

enum _PlansView { active, closed }

class ExecutionPlansPage extends ConsumerWidget {
  const ExecutionPlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    Widget body({required bool inMasterDetail}) => AppRefreshIndicator(
      onRefresh: () async {
        ref.invalidate(executionPlansProvider);
        ref.invalidate(executionClosedPlansProvider);
        ref.invalidate(executionOpenActionsProvider);
        ref.invalidate(executionClosedActionsProvider);
        ref.invalidate(executionRecentProgressProvider);
        ref.invalidate(executionActionRelationsProvider);
        await ref.read(executionOpenActionsProvider.future);
      },
      child: _PlansBody(inMasterDetail: inMasterDetail),
    );
    return ShellTabScaffold(
      title: l10n.executionPlansTitle,
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
        routePath: ExecutionRoutes.plans,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (GoRouter.maybeOf(context) == null ||
                !MasterDetailLayout.shouldUseMasterDetail(
                  constraints.maxWidth,
                )) {
              return body(inMasterDetail: false);
            }
            return MasterDetailLayout(
              master: body(inMasterDetail: true),
              detail: _planDetail(context, selectedQueryOf(context)),
            );
          },
        ),
      ),
    );
  }
}

class _PlansBody extends ConsumerStatefulWidget {
  const _PlansBody({required this.inMasterDetail});

  final bool inMasterDetail;

  @override
  ConsumerState<_PlansBody> createState() => _PlansBodyState();
}

class _PlansBodyState extends ConsumerState<_PlansBody> {
  _PlansView _view = _PlansView.active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plansAsync = ref.watch(
      _view == _PlansView.active
          ? executionPlansProvider
          : executionClosedPlansProvider,
    );
    final actionsAsync = ref.watch(
      _view == _PlansView.active
          ? executionOpenActionsProvider
          : executionClosedActionsProvider,
    );
    final openActionsAsync = ref.watch(executionOpenActionsProvider);
    final relations = ref.watch(executionActionRelationsProvider).value;
    final error =
        plansAsync.error ?? actionsAsync.error ?? openActionsAsync.error;
    if (error != null) {
      return AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: userSafeErrorMessage(context, error),
        retryLabel: l10n.commonRetry,
        onRetry: () {
          ref.invalidate(executionPlansProvider);
          ref.invalidate(executionClosedPlansProvider);
          ref.invalidate(executionOpenActionsProvider);
          ref.invalidate(executionClosedActionsProvider);
        },
      );
    }
    if ((plansAsync.isLoading && !plansAsync.hasValue) ||
        (actionsAsync.isLoading && !actionsAsync.hasValue) ||
        (openActionsAsync.isLoading && !openActionsAsync.hasValue)) {
      return AppListPageSkeleton(padding: shellTabContentPadding(context));
    }

    final plans = plansAsync.value ?? const <ExecutionPlan>[];
    final actions = actionsAsync.value ?? const <ExecutionAction>[];
    final openActions = openActionsAsync.value ?? const <ExecutionAction>[];
    final activeView = _view == _PlansView.active;
    final planIds = plans.map((plan) => plan.id).toSet();
    final inboxActions = actions
        .where((action) => action.planId == null)
        .toList(growable: false);
    final unplacedActions = activeView
        ? openActions
              .where(
                (action) =>
                    action.planId != null && !planIds.contains(action.planId),
              )
              .toList(growable: false)
        : const <ExecutionAction>[];
    final actionCountByPlan = <String, int>{};
    final blockedCountByPlan = <String, int>{};
    for (final action in openActions) {
      final planId = action.planId;
      if (planId == null) continue;
      actionCountByPlan.update(planId, (count) => count + 1, ifAbsent: () => 1);
      if (action.status == ExecutionActionStatus.blocked) {
        blockedCountByPlan.update(
          planId,
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
            onTap: () => setState(() => _view = _PlansView.active),
          ),
        ),
        (_) => const SizedBox(height: AppSpacing.s16),
      ],
    ];
    if (plans.isEmpty && actions.isEmpty) {
      itemBuilders.add(
        (_) => AppEmptyState(
          icon: activeView ? FLucideIcons.listTodo : FLucideIcons.archive,
          title: activeView
              ? l10n.executionPlansEmptyTitle
              : l10n.executionPlansClosedEmptyTitle,
          message: activeView
              ? l10n.executionPlansEmptyBody
              : l10n.executionPlansClosedEmptyBody,
          action: activeView
              ? FButton(
                  onPress: () => showExecutionActionSheet(context: context),
                  child: Text(l10n.executionCreateActionTitle),
                )
              : null,
        ),
      );
    }
    _appendActions(
      context,
      itemBuilders,
      actions: inboxActions,
      title: activeView
          ? l10n.executionInboxSection
          : l10n.executionClosedActionsSection,
      icon: activeView ? FLucideIcons.inbox : FLucideIcons.archive,
      relations: relations,
    );
    _appendActions(
      context,
      itemBuilders,
      actions: unplacedActions,
      title: l10n.executionUnplacedActionsSection,
      icon: FLucideIcons.listTodo,
      relations: relations,
    );
    if (plans.isNotEmpty) {
      itemBuilders
        ..add(
          (_) => ExecutionSectionHeader(
            title: l10n.executionPlansSection,
            count: plans.length,
            icon: FLucideIcons.layers,
          ),
        )
        ..add((_) => const SizedBox(height: AppSpacing.s8));
      for (final plan in plans) {
        itemBuilders.add(
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: AppSelectedRow(
              selected:
                  widget.inMasterDetail && selectedQueryOf(context) == plan.id,
              color: DomainAccents.execution.resolve(
                context.appTheme.brightness,
              ),
              child: ExecutionPlanCardController(
                plan: plan,
                openActionCount: actionCountByPlan[plan.id] ?? 0,
                blockedActionCount: blockedCountByPlan[plan.id] ?? 0,
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
                onOpen: () => _openPlan(
                  context,
                  inMasterDetail: widget.inMasterDetail,
                  id: plan.id,
                ),
              ),
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
              onTap: () => setState(() => _view = _PlansView.closed),
            ),
          ),
        );
    }

    return AdaptiveContentFrame(
      maxWidth: Breakpoints.readingColumn,
      expandSinglePrimary: true,
      padding: EdgeInsets.zero,
      primary: AppEntranceScope(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellTabContentPadding(context),
          itemCount: itemBuilders.length,
          itemBuilder: (context, index) => AppOnceEntrance(
            index: index,
            child: itemBuilders[index](context),
          ),
        ),
      ),
    );
  }

  void _appendActions(
    BuildContext context,
    List<WidgetBuilder> builders, {
    required List<ExecutionAction> actions,
    required String title,
    required IconData icon,
    required ExecutionRelations? relations,
  }) {
    if (actions.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    builders
      ..add(
        (_) => ExecutionSectionHeader(
          title: title,
          count: actions.length,
          icon: icon,
        ),
      )
      ..add((_) => const SizedBox(height: AppSpacing.s8));
    for (final action in actions) {
      builders.add(
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s8),
          child: ExecutionActionCardController(
            action: action,
            planLabel: relations?.planLabel(action.planId),
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
    builders.add((_) => const SizedBox(height: AppSpacing.s8));
  }
}

Widget _planDetail(BuildContext context, String? selected) {
  if (selected == null || selected.isEmpty) {
    return MasterDetailEmpty(
      message: AppLocalizations.of(context).executionPlansSelectItem,
      icon: FLucideIcons.layers,
    );
  }
  return ExecutionPlanDetailPage(planId: selected);
}

void _openPlan(
  BuildContext context, {
  required bool inMasterDetail,
  required String id,
}) {
  if (inMasterDetail) {
    replaceSelectedQuery(context, path: ExecutionRoutes.plans, selected: id);
    return;
  }
  context.push(ExecutionRoutes.plan(id));
}
