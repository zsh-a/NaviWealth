import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Text composer at the bottom of the chat. Multiline TextField with a
/// send / cancel button on the right. ⌘/Ctrl + Enter sends; plain Enter
/// inserts a newline (matches conventions in chat-style apps where
/// users want to compose multi-paragraph questions about their
/// portfolio).
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.isStreaming,
    required this.onSend,
    required this.onCancel,
    this.initialText,
  });

  final bool isStreaming;

  /// Optional text to pre-fill the composer with (e.g. from "Ask AI" in
  /// the command palette).
  final String? initialText;
  final ValueChanged<String> onSend;
  final VoidCallback onCancel;

  bool get _busy => isStreaming;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

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

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _controller.clear();
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.background,
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: _onKey,
                  child: FTextField(
                    // No keystroke setState — `_TrailingButton` listens
                    // to the controller directly so a keypress only
                    // rebuilds the send button, not the whole composer
                    // (FTextField + AnimatedSwitcher + SafeArea + …).
                    control: FTextFieldControl.managed(controller: _controller),
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 6,
                    enabled: !widget._busy,
                    hint: widget.isStreaming
                        ? l10n.aiChatComposerHintStreaming
                        : l10n.aiChatComposerHintIdle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _TrailingButton(
                controller: _controller,
                isStreaming: widget.isStreaming,
                onSend: _send,
                onCancel: widget.onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scoped trailing-button rebuild. Listens to the composer's
/// [TextEditingController] so a keystroke only repaints this 36×36 area
/// rather than the entire composer (which previously did `setState({})`
/// on every keypress and rebuilt the FTextField + AnimatedSwitcher).
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
            child: const Icon(Icons.stop),
          ),
        );
      }
      return FTooltip(
        key: const ValueKey('send'),
        tipBuilder: (_, _) => Text(l10n.aiChatComposerSendTooltip),
        child: FButton.icon(
          variant: FButtonVariant.primary,
          onPress: canSend ? onSend : null,
          child: const Icon(Icons.arrow_upward),
        ),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final canSend = !isStreaming && controller.text.trim().isNotEmpty;
        // AnimatedSwitcher's keyed children cross-fade only when
        // isStreaming flips — toggling `canSend` keeps the same key, so
        // a keystroke doesn't trigger a transition.
        return AnimatedSwitcher(
          duration: Motion.fast,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: current(canSend),
        );
      },
    );
  }
}
