import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/lifeos/action_dispatcher.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '_widgets.dart';

/// A source-preserving Knowledge → Execution handoff.
///
/// The source family and row id are stable, so app composition can return the
/// existing open action instead of creating duplicate follow-ups.
class KnowledgeExecutionAction extends ConsumerStatefulWidget {
  const KnowledgeExecutionAction({
    super.key,
    required this.draftTitle,
    required this.draftNote,
    required this.sourceRowFamily,
    required this.sourceRowId,
    required this.prompt,
    this.dueAt,
  });

  final String draftTitle;
  final String draftNote;
  final String sourceRowFamily;
  final String sourceRowId;
  final String prompt;
  final DateTime? dueAt;

  @override
  ConsumerState<KnowledgeExecutionAction> createState() =>
      _KnowledgeExecutionActionState();
}

class _KnowledgeExecutionActionState
    extends ConsumerState<KnowledgeExecutionAction> {
  bool _creating = false;
  String? _createdActionId;

  LifeActionSource get _source =>
      (rowFamily: widget.sourceRowFamily, rowId: widget.sourceRowId);

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(lifeOpenActionCountProvider).value != null;
    if (!available) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final linked = ref.watch(lifeLinkedActionProvider(_source)).value;
    final actionId = _createdActionId ?? linked?.id;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: KnowledgePromptSurface(
        child: Row(
          children: [
            Icon(
              actionId == null
                  ? FLucideIcons.listPlus
                  : FLucideIcons.circleCheck,
              size: AppIconSizes.sm,
              color: colors.primary,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                actionId == null ? widget.prompt : l10n.knowledgeActionLinked,
                style: context.captionStyle,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Flexible(
              child: AppBusyButton(
                label: actionId == null
                    ? l10n.knowledgeActionCreate
                    : l10n.knowledgeActionOpen,
                busy: _creating,
                size: FButtonSizeVariant.sm,
                variant: actionId == null
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                onPress: actionId == null
                    ? _create
                    : () => _openAction(actionId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    final l10n = AppLocalizations.of(context);
    try {
      final actionId = await ref.read(lifeActionDispatcherProvider)(
        LifeActionDraft(
          title: widget.draftTitle,
          note: widget.draftNote,
          sourceDomain: 'knowledge',
          sourceRowFamily: widget.sourceRowFamily,
          sourceRowId: widget.sourceRowId,
          dueAt: widget.dueAt,
        ),
      );
      if (!mounted) return;
      if (actionId == null) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeActionUnavailable,
        );
        return;
      }
      setState(() => _createdActionId = actionId);
      ref.invalidate(lifeLinkedActionProvider(_source));
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeActionCreated,
      );
    } catch (error) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeActionFailed('$error'),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openAction(String actionId) {
    final route = ref.read(lifeActionRouteBuilderProvider)?.call(actionId);
    if (route != null) context.push(route);
  }
}
