import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/composition/proposal_apply_state.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../../../core/ai/progress/long_task_progress.dart';
import '../../../../core/ai/runtime/device/tools/ask_user_tool.dart'
    show kAskUserToolName;
import '../../../../core/ai/visual/visual.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/chat_models.dart';
import '../../state/chat_controller.dart';
import '../ai_transparency_badge.dart';
import '../decision_card.dart';
import '../decision_request.dart';
import '../proposals/propose_batch_actions.dart';
import '../proposals/propose_card.dart';
import '../reply_chips.dart';
import '../tools/tool_invocation_card.dart' show friendlyToolName;
import '../tools/tool_invocation_inline.dart';

part 'assistant.dart';
part 'streaming.dart';
part 'support_views.dart';

/// Renders a single chat row. Roles map to distinct visual treatments:
///
///  - `user` — right-aligned filled bubble in the primary container.
///  - `assistant` — left-aligned with a subtle surface bubble; tool
///    invocations stack underneath.
///  - `system` — centered chip-style notice ("已折叠 N 条历史").
///  - `error` — left-aligned bubble in the error container colour.
///
/// Streaming assistant turns get a small pulsing dot at the end of the
/// text so the user can tell content is still arriving.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.sessionId,
    required this.message,
    this.onReplyChip,
    this.onDecisionSelect,
    this.invocationIntent,
    this.isLastAssistant = false,
    this.isLastUser = false,
    this.suggestCannedReplies = true,
    this.animateIn = true,
  });

  final String sessionId;
  final ChatMessage message;

  /// When non-null, completed assistant turns render reply
  /// chips below the body and call this back with the tapped chip
  /// text. Caller sends it as the next user turn. Streaming/error
  /// messages render no chips regardless.
  final void Function(String chip)? onReplyChip;
  final void Function(DecisionSelectionRequest selection)? onDecisionSelect;

  /// When false, the generic rules-based reply chips
  /// (`suggestReplyChips`) are suppressed — only a content-derived
  /// clickable choice list (parsed from a menu the model actually wrote)
  /// renders. The conversation sheet sets this false so every turn isn't
  /// trailed by canned "展开细节 / 对比" suggestions; the invocation
  /// surface keeps them (true) as its guided next-step affordance.
  final bool suggestCannedReplies;

  /// Invocation intent that triggered this turn. Drives the rules-based chip suggester.
  final String? invocationIntent;

  /// Whether this is the trailing assistant message in the timeline.
  /// Only the trailing one gets a "regenerate" affordance — discarding
  /// a mid-thread assistant reply would silently throw away every
  /// follow-up turn, which is almost never what the user wants.
  final bool isLastAssistant;

  /// Whether this is the trailing user message in the timeline. Only
  /// the trailing user message gets the "edit & resend" affordance —
  /// mid-thread edit would silently discard every follow-up turn,
  /// which is destructive and almost never the user intent.
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
        onReplyChip: onReplyChip,
        onDecisionSelect: onDecisionSelect,
        invocationIntent: invocationIntent,
        isLastAssistant: isLastAssistant,
        suggestCannedReplies: suggestCannedReplies,
      ),
    };
    if (!animateIn) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(message.id),
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotionPolicy.duration(context, Motion.medium),
      curve: Motion.standardDecelerate,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
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

  /// Only the trailing user message gets the edit-and-resend
  /// affordance — see [MessageBubble.isLastUser].
  final bool isLastUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final turn = ref.watch(chatControllerProvider(sessionId));
    // Edit is gated to: (a) the trailing user turn, (b) not currently
    // streaming/flushing — otherwise tapping mid-stream would race the
    // in-flight pipeline and produce duplicates.
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
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Semantics(
                    container: true,
                    label: l10n.aiChatSemanticsUserMessage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s12,
                        vertical: AppSpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppRadius.sm),
                          topRight: Radius.circular(AppRadius.xs),
                          bottomLeft: Radius.circular(AppRadius.sm),
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
            ],
          ),
          if (showEdit)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: _ActionButton(
                icon: FLucideIcons.pencil,
                label: l10n.aiChatEditUserMessage,
                onPressed: () => _editAndResend(context, ref),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editAndResend(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: message.content);
    final result = await showAppFormSheet<String>(
      context: context,
      builder: (ctx) => AppSheet(
        title: l10n.aiChatEditUserMessageTitle,
        footer: AppSheetFooter(
          submitLabel: l10n.aiChatEditUserMessageSubmit,
          cancelLabel: l10n.commonCancel,
          // Treat as destructive — saving discards the existing AI
          // reply (+ any later turns) before re-running the prompt.
          destructive: true,
          onSubmit: () => Navigator.of(ctx).pop(controller.text.trim()),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.aiChatEditUserMessageWarning,
              style: context.captionStyle.copyWith(height: 1.4),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              control: FTextFieldControl.managed(controller: controller),
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    if (result == message.content.trim()) return;
    if (!context.mounted) return;
    await ref
        .read(chatControllerProvider(sessionId).notifier)
        .editAndResend(messageId: message.id, newContent: result);
  }
}
