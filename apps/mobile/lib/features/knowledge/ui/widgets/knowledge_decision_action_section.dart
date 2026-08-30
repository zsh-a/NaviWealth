import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/lifeos/action_dispatcher.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/knowledge_models.dart';

const String _knowledgeDecisionRowFamily = 'know:knowledge_decisions';

class KnowledgeDecisionActionSection extends ConsumerWidget {
  const KnowledgeDecisionActionSection({super.key, required this.decision});

  final KnowledgeDecision decision;

  LifeActionSource get _source =>
      (rowFamily: _knowledgeDecisionRowFamily, rowId: decision.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability = ref.watch(lifeOpenActionCountProvider);
    if (availability.isLoading) {
      return _section(context, children: const [kDefaultLoading]);
    }
    if (availability.hasError) return const SizedBox.shrink();
    if (availability.asData?.value == null) {
      final l10n = AppLocalizations.of(context);
      return _section(
        context,
        children: [
          Text(
            l10n.knowledgeDecisionActionUnavailable,
            style: context.bodyCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s10),
          SizedBox(
            width: double.infinity,
            child: AppQuietButton(
              label: l10n.agentSettingsManageDomains,
              prefix: const Icon(FLucideIcons.settings2),
              onPress: () => context.push(SettingsRoutes.domains),
            ),
          ),
        ],
      );
    }

    final linked = ref.watch(lifeLinkedActionProvider(_source));
    return linked.when(
      loading: () => _section(context, children: const [kDefaultLoading]),
      error: (_, _) => const SizedBox.shrink(),
      data: (action) =>
          _ActionContent(decision: decision, action: action, source: _source),
    );
  }

  Widget _section(BuildContext context, {required List<Widget> children}) {
    return AppSection.item(
      title: AppLocalizations.of(context).knowledgeDecisionActionTitle,
      children: children,
    );
  }
}

class _ActionContent extends ConsumerStatefulWidget {
  const _ActionContent({
    required this.decision,
    required this.action,
    required this.source,
  });

  final KnowledgeDecision decision;
  final LifeLinkedAction? action;
  final LifeActionSource source;

  @override
  ConsumerState<_ActionContent> createState() => _ActionContentState();
}

class _ActionContentState extends ConsumerState<_ActionContent> {
  var _creating = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final action = widget.action;
    if (action != null) {
      return AppSection.item(
        title: l10n.knowledgeDecisionActionTitle,
        trailing: FBadge(child: Text(_stateLabel(l10n, action.state))),
        children: [
          Text(
            l10n.knowledgeDecisionActionLinked,
            style: context.bodyCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s10),
          SizedBox(
            width: double.infinity,
            child: AppQuietButton(
              key: const Key('knowledge-decision-open-action'),
              label: l10n.knowledgeDecisionOpenAction,
              prefix: const Icon(FLucideIcons.externalLink),
              onPress: _openAction,
            ),
          ),
        ],
      );
    }
    return AppSection.item(
      title: l10n.knowledgeDecisionActionTitle,
      children: [
        Text(
          l10n.knowledgeDecisionActionDescription,
          style: context.bodyCaptionStyle,
        ),
        const SizedBox(height: AppSpacing.s10),
        SizedBox(
          width: double.infinity,
          child: AppActionButton(
            key: const Key('knowledge-decision-create-action'),
            onPress: _creating ? null : _createAction,
            child: Text(
              _creating
                  ? l10n.commonSaving
                  : l10n.knowledgeDecisionCreateAction,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createAction() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.knowledgeDecisionActionConfirmTitle),
      body: Text(l10n.knowledgeDecisionActionConfirmBody),
      confirmLabel: l10n.knowledgeDecisionCreateAction,
      cancelLabel: l10n.commonCancel,
      icon: FLucideIcons.listTodo,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _creating = true);
    try {
      final decision = widget.decision;
      final expected = decision.expectedOutcome?.trim();
      final note = StringBuffer(decision.question);
      if (expected != null && expected.isNotEmpty) {
        note
          ..writeln()
          ..write(l10n.knowledgeDecisionActionExpectedOutcome(expected));
      }
      final id = await ref.read(lifeActionDispatcherProvider)(
        LifeActionDraft(
          title: decision.selectedLabel.trim().isEmpty
              ? decision.question
              : decision.selectedLabel,
          note: note.toString(),
          sourceDomain: 'knowledge',
          sourceRowFamily: widget.source.rowFamily,
          sourceRowId: widget.source.rowId,
          sourceLabelSnapshot: decision.question,
        ),
      );
      if (!mounted || id == null) return;
      await recordProductMetric(
        () => ref.read(productMetricsProvider.notifier),
        ProductFunnelEvent.knowledgeDecisionActionCreated,
        success: true,
      );
      if (!mounted) return;
      ref.invalidate(lifeLinkedActionProvider(widget.source));
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeDecisionActionCreated,
      );
      final routeBuilder = ref.read(lifeActionRouteBuilderProvider);
      if (routeBuilder != null && mounted) {
        await context.push<void>(routeBuilder(id));
      }
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'create action from knowledge decision',
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openAction() {
    final action = widget.action;
    final routeBuilder = ref.read(lifeActionRouteBuilderProvider);
    if (action != null && routeBuilder != null) {
      context.push(routeBuilder(action.id));
    }
  }
}

String _stateLabel(AppLocalizations l10n, LifeActionState state) =>
    switch (state) {
      LifeActionState.todo => l10n.executionStatusTodo,
      LifeActionState.doing => l10n.executionStatusDoing,
      LifeActionState.blocked => l10n.executionStatusBlocked,
      LifeActionState.done => l10n.executionStatusDone,
      LifeActionState.dropped => l10n.executionStatusDropped,
    };
