import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/composition/ai_context.dart';
import '../../../../core/ai/composition/proposal_apply_state.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../../../core/ai/progress/long_task_progress.dart';
import '../../../../core/ai/runtime/device/tools/ask_user_tool.dart'
    show kAskUserToolName;
import '../../../../core/ai/trace/trace.dart';
import '../../../../core/ai/visual/visual.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/chat_models.dart';
import '../../state/chat_controller.dart';
import '../../state/composer_draft.dart';
import '../ai_navigation.dart';
import '../ai_transparency_badge.dart';
import '../decision_card.dart';
import '../decision_request.dart';
import '../proposals/propose_batch_actions.dart';
import '../proposals/propose_card.dart';
import '../reply_chips.dart';
import '../tools/renderers/tool_invocation_renderers.dart'
    show isRichToolOutput, netWorthSparkValues, richToolPriority, ToolMiniSpark;
import '../tools/tool_invocation_card.dart' show friendlyToolName;
import '../tools/tool_invocation_inline.dart';

part 'assistant.dart';
part 'streaming.dart';
part 'support_views.dart';

/// Renders a single chat row. Roles map to distinct visual treatments:
///
///  - `user` — right-aligned filled bubble in the primary container.
///  - `assistant` — left-aligned flat prose; tool results stack underneath.
///  - `system` — centered chip-style notice ("已折叠 N 条历史").
///  - `error` — left-aligned with a soft destructive accent.
///
/// Streaming assistant turns get a small pulsing caret at the end of the
/// text so the user can tell content is still arriving.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.sessionId,
    required this.message,
    this.onDecisionSelect,
    this.isLastAssistant = false,
    this.isLastUser = false,
    this.animateIn = true,
  });

  final String sessionId;
  final ChatMessage message;
  final void Function(DecisionSelectionRequest selection)? onDecisionSelect;

  /// Whether this is the trailing assistant message in the timeline.
  /// Only the trailing one gets a "regenerate" affordance.
  final bool isLastAssistant;

  /// Whether this is the trailing user message in the timeline. Only
  /// the trailing user message gets the "edit" affordance.
  final bool isLastUser;

  /// Historical messages are often mounted in bulk when the sheet opens.
  /// Animating each one competes with the sheet transition; only messages
  /// inserted after the first snapshot should animate in.
  final bool animateIn;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (message.role) {
      ChatRole.system => _SystemNotice(text: message.content),
      ChatRole.user => _UserBubble(
        sessionId: sessionId,
        message: message,
        isLastUser: isLastUser,
      ),
      ChatRole.assistant || ChatRole.error => _AssistantBubble(
        sessionId: sessionId,
        message: message,
        onDecisionSelect: onDecisionSelect,
        isLastAssistant: isLastAssistant,
      ),
    };
    return AppEntrance(
      key: ValueKey(message.id),
      enabled: animateIn,
      child: child,
    );
  }
}

class _UserBubble extends ConsumerWidget {
  const _UserBubble({
    required this.sessionId,
    required this.message,
    this.isLastUser = false,
  });

  final String sessionId;
  final ChatMessage message;
  final bool isLastUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final turn = ref.watch(chatControllerProvider(sessionId));
    final showEdit = isLastUser && !turn.isBusy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AdaptiveMaxWidth.narrow,
                  ),
                  child: Semantics(
                    container: true,
                    label: l10n.aiChatSemanticsUserMessage,
                    child: GestureDetector(
                      onLongPress: () =>
                          _showUserActions(context, ref, canEdit: showEdit),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s14,
                          vertical: AppSpacing.s10,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(AppRadius.lg),
                            topRight: Radius.circular(AppRadius.lg),
                            bottomLeft: Radius.circular(AppRadius.lg),
                            bottomRight: Radius.circular(AppRadius.sm),
                          ),
                        ),
                        child: SelectableText(
                          message.content,
                          style: typography.body.sm.copyWith(
                            height: 1.5,
                            color: colors.primaryForeground,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (showEdit)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: _IconAction(
                icon: FLucideIcons.pencil,
                tooltip: l10n.aiChatEditUserMessage,
                onPressed: () => _loadIntoComposer(context, ref),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showUserActions(
    BuildContext context,
    WidgetRef ref, {
    required bool canEdit,
  }) async {
    final l10n = AppLocalizations.of(context);
    AppInteraction.signal(AppInteractionIntent.select);
    final actions = <AppAdaptiveAction>[
      AppAdaptiveAction(
        icon: FLucideIcons.copy,
        title: l10n.aiChatMessageCopy,
        onPress: () async {
          await Clipboard.setData(ClipboardData(text: message.content));
          if (!context.mounted) return;
          AppMessenger.show(
            context,
            ToastKind.success,
            l10n.aiChatMessageCopied,
          );
        },
      ),
      if (canEdit)
        AppAdaptiveAction(
          icon: FLucideIcons.pencil,
          title: l10n.aiChatEditUserMessage,
          onPress: () => _loadIntoComposer(context, ref),
        ),
    ];
    await showAppSheet<void>(
      context: context,
      title: l10n.aiChatMessageActionsTitle,
      builder: (sheetContext) => AppActionSheetList(
        children: [
          for (final action in actions)
            AppActionSheetTile(
              icon: action.icon,
              title: action.title,
              onPress: () {
                Navigator.of(sheetContext).pop();
                action.onPress();
              },
            ),
        ],
      ),
    );
  }

  void _loadIntoComposer(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.read(chatComposerDraftProvider(sessionId).notifier).state =
        ComposerDraft(text: message.content, replaceMessageId: message.id);
    AppMessenger.show(context, ToastKind.info, l10n.aiChatEditUserMessageHint);
  }
}
