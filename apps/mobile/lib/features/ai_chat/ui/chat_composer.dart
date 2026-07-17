import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../state/composer_draft.dart';
import 'ai_navigation.dart';

/// Text composer at the bottom of the chat. Multiline TextField with a
/// send / cancel button on the right. ⌘/Ctrl + Enter sends; plain Enter
/// inserts a newline.
///
/// When [sessionId] is set the composer also:
///  - shows the active LLM profile as a quiet caption under the field;
///  - listens for [chatComposerDraftProvider] (edit-and-resend / prefills).
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.isStreaming,
    required this.onSend,
    required this.onCancel,
    this.sessionId,
    this.initialText,
    this.onEditResend,
  });

  final bool isStreaming;
  final String? sessionId;

  /// Optional text to pre-fill once on mount (command palette / sheet).
  final String? initialText;
  final ValueChanged<String> onSend;
  final VoidCallback onCancel;

  /// Called when the user submits while an edit draft is active
  /// ([ComposerDraft.replaceMessageId] non-null). Falls back to [onSend]
  /// when null.
  final void Function(String messageId, String text)? onEditResend;

  bool get _busy => isStreaming;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// When set, next submit replaces this user turn instead of appending.
  String? _replaceMessageId;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _applyDraft(ComposerDraft draft) {
    setState(() {
      _controller
        ..text = draft.text
        ..selection = TextSelection.collapsed(offset: draft.text.length);
      _replaceMessageId = draft.replaceMessageId;
    });
    _focusNode.requestFocus();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final replaceId = _replaceMessageId;
    setState(() {
      _replaceMessageId = null;
      _controller.clear();
    });
    if (replaceId != null) {
      final handler = widget.onEditResend;
      if (handler != null) {
        handler(replaceId, text);
        return;
      }
    }
    widget.onSend(text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final modifierHeld =
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    if (!modifierHeld) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessionId = widget.sessionId;

    if (sessionId != null) {
      ref.listen<ComposerDraft?>(chatComposerDraftProvider(sessionId), (
        _,
        next,
      ) {
        if (next == null) return;
        _applyDraft(next);
        // Consume so a rebuild doesn't re-apply.
        ref.read(chatComposerDraftProvider(sessionId).notifier).state = null;
      });
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.background,
        border: Border(
          top: BorderSide(
            color: context.theme.colors.border.withValues(
              alpha: AppOpacity.scrim,
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s12,
          AppSpacing.s8,
          AppSpacing.s12,
          AppSpacing.s12,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sessionId != null) const _ProfileCaption(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Focus(
                      onKeyEvent: _onKey,
                      child: FTextField(
                        control: FTextFieldControl.managed(
                          controller: _controller,
                        ),
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 6,
                        enabled: !widget._busy,
                        hint: widget.isStreaming
                            ? l10n.aiChatComposerHintStreaming
                            : (_replaceMessageId != null
                                  ? l10n.aiChatEditUserMessageTitle
                                  : l10n.aiChatComposerHintIdle),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  _TrailingButton(
                    controller: _controller,
                    isStreaming: widget.isStreaming,
                    onSend: _send,
                    onCancel: widget.onCancel,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet caption above the field: active model name, tappable to settings.
class _ProfileCaption extends ConsumerWidget {
  const _ProfileCaption();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(llmCredentialsProvider).asData?.value;
    final active = creds?.active;
    if (active == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FTooltip(
          tipBuilder: (_, _) => Text(l10n.aiChatProfileChipTooltip),
          child: FTappable(
            onPress: () => pushFromAiSurface(context, SettingsRoutes.aiLlm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AiSparkle(size: 11),
                const SizedBox(width: AppSpacing.s4),
                Text(
                  active.displayName,
                  style: AiType.meta(context).copyWith(
                    color: AiTone.muted(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Scoped trailing-button rebuild. Listens to the composer's
/// [TextEditingController] so a keystroke only repaints this area.
class _TrailingButton extends StatelessWidget {
  const _TrailingButton({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget current(bool canSend) {
      if (isStreaming) {
        return FTooltip(
          key: const ValueKey('stop'),
          tipBuilder: (_, _) => Text(l10n.aiChatComposerStopTooltip),
          child: FButton.icon(
            variant: FButtonVariant.secondary,
            onPress: onCancel,
            child: const Icon(FLucideIcons.square),
          ),
        );
      }
      return FTooltip(
        key: const ValueKey('send'),
        tipBuilder: (_, _) => Text(l10n.aiChatComposerSendTooltip),
        child: FButton.icon(
          variant: FButtonVariant.primary,
          onPress: canSend ? onSend : null,
          child: const Icon(FLucideIcons.arrowUp),
        ),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final canSend = !isStreaming && controller.text.trim().isNotEmpty;
        return AnimatedSwitcher(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: current(canSend),
        );
      },
    );
  }
}
