import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/lifeos/action_dispatcher.dart';
import '../../../core/lifeos/domain_pack.dart';
import '../../../core/lifeos/ui/source_action_control.dart';
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
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final event = widget.event;
    final suggestion = event.actionSuggestion;
    final actionTitle = event.localizedActionTitle(l10n);
    final canCreate = suggestion?.sourceRowId != null && actionTitle != null;
    final executionPack = ref
        .watch(activeDomainPacksProvider)
        .where((pack) => pack.scope == DomainScope.execution)
        .firstOrNull;
    final executionEnabled = widget.executionEnabled || executionPack != null;

    return AppSheet(
      title: l10n.lifeSignalDetailTitle,
      subtitle: event.localizedTitle(l10n),
      footer: canCreate && !executionEnabled
          ? AppSheetFooter(
              submitLabel: l10n.lifeSignalEnableExecution,
              cancelLabel: l10n.commonCancel,
              onSubmit: _openDomainSettings,
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
                ],
              ),
            ),
          ],
          if (canCreate && executionEnabled) ...[
            const SizedBox(height: AppSpacing.s12),
            SourceActionControl(
              source: (
                rowFamily: suggestion!.sourceRowFamily,
                rowId: suggestion.sourceRowId!,
              ),
              createLabel: l10n.lifeSignalCreateAction,
              openLabel: l10n.lifeSignalOpenExecution,
              confirmTitle: l10n.lifeSignalActionConfirmTitle,
              confirmBody: l10n.lifeSignalActionConfirmBody(
                actionTitle,
                event.localizedTitle(l10n),
              ),
              successMessage: l10n.lifeSignalActionCreated,
              onBusyChanged: (busy) => widget.dirty.busy = busy,
              beforeOpen: () => Navigator.of(context).pop(),
              openAfterCreate: false,
              buildDraft: (replacesActionId) => LifeActionDraft(
                title: actionTitle,
                note: event.localizedActionNote(l10n),
                sourceDomain: event.domain.wire,
                sourceRowFamily: suggestion.sourceRowFamily,
                sourceRowId: suggestion.sourceRowId!,
                sourceLabelSnapshot: _domainLabel(l10n, event.domain),
                scheduledFor: DateTime.now().toUtc(),
                priority: event.priority == LifeSignalPriority.high
                    ? 'high'
                    : 'normal',
                replacesActionId: replacesActionId,
              ),
            ),
          ],
          if (event.routePath != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                onPress: widget.dirty.busy ? null : _openSource,
                variant: FButtonVariant.outline,
                child: Text(l10n.lifeSignalOpenSource),
              ),
            ),
          ],
        ],
      ),
    );
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
