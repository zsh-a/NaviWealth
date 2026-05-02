import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.isFlushing = false,
    this.initialText,
  });

  final bool isStreaming;

  /// Pre-chat sync gate (FIR-71) is draining the OpLog. The composer
  /// disables input and shows "正在同步..." for the typically sub-second
  /// window while we wait for `/sync/push` to land.
  final bool isFlushing;

  /// Optional text to pre-fill the composer with (e.g. from "Ask AI" in
  /// the command palette).
  final String? initialText;
  final ValueChanged<String> onSend;
  final VoidCallback onCancel;

  bool get _busy => isStreaming || isFlushing;

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
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final modifierHeld = pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    if (!modifierHeld) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final canSend = !widget._busy && _controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Spacing.s12,
        Spacing.s8,
        Spacing.s12,
        Spacing.s12,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  minLines: 1,
                  maxLines: 6,
                  enabled: !widget._busy,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: widget.isFlushing
                        ? l10n.aiChatComposerHintFlushing
                        : widget.isStreaming
                            ? l10n.aiChatComposerHintStreaming
                            : l10n.aiChatComposerHintIdle,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.s12,
                      vertical: Spacing.s12,
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: Radii.brMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.s8),
            if (widget.isStreaming)
              IconButton.filledTonal(
                onPressed: widget.onCancel,
                tooltip: l10n.aiChatComposerStopTooltip,
                icon: const Icon(Icons.stop),
              )
            else if (widget.isFlushing)
              const Padding(
                padding: EdgeInsets.all(Spacing.s8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton.filled(
                onPressed: canSend ? _send : null,
                tooltip: l10n.aiChatComposerSendTooltip,
                icon: const Icon(Icons.arrow_upward),
              ),
          ],
        ),
      ),
    );
  }
}
