import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/lifeos/domain_pack.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/life_event.dart';
import 'life_event_l10n.dart';

Future<void> showLifeSignalSheet({
  required BuildContext context,
  required LifeEvent event,
  required bool executionEnabled,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<void>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _LifeSignalSheet(
      event: event,
      executionEnabled: executionEnabled,
      dirty: dirty,
    ),
  ).whenComplete(dirty.dispose);
}

class _LifeSignalSheet extends ConsumerStatefulWidget {
  const _LifeSignalSheet({
    required this.event,
    required this.executionEnabled,
    required this.dirty,
  });

  final LifeEvent event;
  final bool executionEnabled;
  final FormDirtyController dirty;

  @override
  ConsumerState<_LifeSignalSheet> createState() => _LifeSignalSheetState();
}

class _LifeSignalSheetState extends ConsumerState<_LifeSignalSheet> {
  static const Uuid _uuid = Uuid();

  bool _applying = false;
  bool _confirming = false;
  bool _created = false;
  String? _createdPath;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = context.appTheme.status;
    final event = widget.event;
    final suggestion = event.actionSuggestion;
    final actionTitle = event.localizedActionTitle(l10n);
    final canCreate = suggestion != null && actionTitle != null;
    final executionPack = ref
        .watch(activeDomainPacksProvider)
        .where((pack) => pack.scope == DomainScope.execution)
        .firstOrNull;
    final executionEnabled = widget.executionEnabled || executionPack != null;
    final executionPath = _createdPath ?? executionPack?.tabPaths.firstOrNull;

    return AppSheet(
      title: l10n.lifeSignalDetailTitle,
      subtitle: event.localizedTitle(l10n),
      footer: canCreate && !_created
          ? AppSheetFooter(
              submitLabel: executionEnabled
                  ? l10n.lifeSignalCreateAction
                  : l10n.lifeSignalEnableExecution,
              cancelLabel: l10n.commonCancel,
              busy: _applying,
              enabled: !_confirming,
              onSubmit: executionEnabled
                  ? () => _createAction(actionTitle)
                  : _openDomainSettings,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            AppStatusBanner(kind: AppStatusKind.error, message: _error!),
            const SizedBox(height: AppSpacing.s12),
          ],
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
                          color: status.success.fg,
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            l10n.lifeSignalActionCreated,
                            style: context.captionStyle.copyWith(
                              color: status.success.fg,
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
          if (_created && executionPath != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                onPress: () => _closeAndGo(executionPath),
                child: Text(l10n.lifeSignalOpenExecution),
              ),
            ),
          ],
          if (event.routePath != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                onPress: _applying || _confirming ? null : _openSource,
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
    if (_applying || _created || _confirming) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    widget.dirty.busy = true;
    final l10n = AppLocalizations.of(context);
    final sourceLabel = widget.event.localizedTitle(l10n);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.lifeSignalActionConfirmTitle),
      body: Text(l10n.lifeSignalActionConfirmBody(actionTitle, sourceLabel)),
      confirmLabel: l10n.lifeSignalCreateAction,
      cancelLabel: l10n.commonCancel,
    );
    if (confirmed != true || !mounted) {
      widget.dirty.busy = false;
      if (mounted) setState(() => _confirming = false);
      return;
    }
    setState(() {
      _confirming = false;
      _applying = true;
    });
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
      final pack = ref
          .read(activeDomainPacksProvider)
          .where((pack) => pack.scope == DomainScope.execution)
          .firstOrNull;
      final id = result.appliedEntityId;
      final table = result.appliedTable;
      setState(() {
        _created = true;
        _createdPath = id == null || table == null
            ? null
            : pack?.sourceRouteResolver?.call('exec:$table', id);
      });
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.lifeSignalActionCreated,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = userSafeErrorMessage(context, error));
      AppMessenger.show(context, ToastKind.error, _error!);
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _applying = false);
    }
  }

  void _openSource() => _closeAndGo(widget.event.routePath!);

  Future<void> _openDomainSettings() async {
    // Keep this suggestion mounted below Settings so enabling the domain can
    // return to the same evidence and explicit create confirmation.
    await GoRouter.of(context).push<void>(
      '${SettingsRoutes.domains}?resume=${DomainScope.execution.wire}',
    );
  }

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
