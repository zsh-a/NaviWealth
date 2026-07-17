import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../execution/composition/execution_route_paths.dart';
import '../domain/life_event.dart';
import 'life_event_l10n.dart';

Future<void> showLifeSignalSheet({
  required BuildContext context,
  required LifeEvent event,
  required bool executionEnabled,
}) {
  return showAppFormSheet<void>(
    context: context,
    builder: (_) =>
        _LifeSignalSheet(event: event, executionEnabled: executionEnabled),
  );
}

class _LifeSignalSheet extends ConsumerStatefulWidget {
  const _LifeSignalSheet({required this.event, required this.executionEnabled});

  final LifeEvent event;
  final bool executionEnabled;

  @override
  ConsumerState<_LifeSignalSheet> createState() => _LifeSignalSheetState();
}

class _LifeSignalSheetState extends ConsumerState<_LifeSignalSheet> {
  static const Uuid _uuid = Uuid();

  bool _applying = false;
  bool _created = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semanticColors = SemanticColors.of(context);
    final event = widget.event;
    final suggestion = event.actionSuggestion;
    final actionTitle = event.localizedActionTitle(l10n);
    final canCreate = suggestion != null && actionTitle != null;

    return AppSheet(
      title: l10n.lifeSignalDetailTitle,
      subtitle: event.localizedTitle(l10n),
      footer: canCreate && !_created && !_applying
          ? AppSheetFooter(
              submitLabel: widget.executionEnabled
                  ? l10n.lifeSignalCreateAction
                  : l10n.lifeSignalEnableExecution,
              cancelLabel: l10n.commonCancel,
              busy: _applying,
              onSubmit: widget.executionEnabled
                  ? () => _createAction(actionTitle)
                  : _openDomainSettings,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoftCard.flat(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      FLucideIcons.shieldCheck,
                      size: AppIconSizes.sm,
                      color: context.theme.colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Text(
                      l10n.lifeSignalEvidenceTitle,
                      style: context.labelStyle,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  event.localizedEvidence(l10n),
                  style: context.bodyCaptionStyle,
                ),
                const SizedBox(height: AppSpacing.s8),
                AppBadge(
                  label: _domainLabel(l10n, event.domain),
                  size: AppBadgeSize.compact,
                  icon: FLucideIcons.database,
                ),
              ],
            ),
          ),
          if (actionTitle != null) ...[
            const SizedBox(height: AppSpacing.s12),
            SoftCard.raised(
              borderless: true,
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(actionTitle, style: context.rowTitleStyle),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    event.localizedActionNote(l10n),
                    style: context.captionStyle,
                  ),
                  if (_created) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          FLucideIcons.circleCheck,
                          size: AppIconSizes.sm,
                          color: semanticColors.success,
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            l10n.lifeSignalActionCreated,
                            style: context.captionStyle.copyWith(
                              color: semanticColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_created) ...[
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                onPress: _openExecution,
                child: Text(l10n.lifeSignalOpenExecution),
              ),
            ),
          ],
          if (event.routePath != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                onPress: _openSource,
                variant: FButtonVariant.outline,
                child: Text(l10n.lifeSignalOpenSource),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createAction(String actionTitle) async {
    if (_applying || _created) return;
    final l10n = AppLocalizations.of(context);
    final sourceLabel = widget.event.localizedTitle(l10n);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.lifeSignalActionConfirmTitle),
      body: Text(l10n.lifeSignalActionConfirmBody(actionTitle, sourceLabel)),
      confirmLabel: l10n.lifeSignalCreateAction,
      cancelLabel: l10n.commonCancel,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _applying = true);
    try {
      final suggestion = widget.event.actionSuggestion!;
      final plan = ReadyProposalPlan(
        proposalId: _uuid.v4(),
        kind: 'execution_action',
        summaryZh: actionTitle,
        payload: <String, Object?>{
          'title': actionTitle,
          'note': widget.event.localizedActionNote(l10n),
          'priority': widget.event.priority == LifeSignalPriority.high
              ? 'high'
              : 'normal',
          'scheduled_for': DateTime.now().toUtc().toIso8601String(),
          'source_domain': widget.event.domain.wire,
          'source_row_family': suggestion.sourceRowFamily,
          if (suggestion.sourceRowId != null)
            'source_row_id': suggestion.sourceRowId,
          'source_label': _domainLabel(l10n, widget.event.domain),
          'reason': widget.event.localizedEvidence(l10n),
        },
      );
      final applier = await ref.read(proposalApplierProvider.future);
      final result = await applier.apply(plan);
      if (result.status != ProposalApplyStatus.applied) {
        throw ProposalApplyException('proposal was not applied');
      }
      if (!mounted) return;
      setState(() => _created = true);
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.lifeSignalActionCreated,
      );
    } catch (error) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.lifeSignalActionFailed('$error'),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _openSource() => _closeAndGo(widget.event.routePath!);

  void _openExecution() => _closeAndGo(ExecutionRoutes.today);

  void _openDomainSettings() => _closeAndGo(SettingsRoutes.domains);

  void _closeAndGo(String path) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(path);
  }
}

String _domainLabel(AppLocalizations l10n, DomainScope scope) =>
    switch (scope) {
      DomainScope.finance => l10n.lifeDomainFinance,
      DomainScope.health => l10n.lifeDomainHealth,
      DomainScope.knowledge => l10n.lifeDomainKnowledge,
      DomainScope.execution => l10n.lifeDomainExecution,
    };
