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
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final canSend = !widget._busy && _controller.text.trim().isNotEmpty;

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
                      fillColor: cs.surfaceContainerHighest.withValues(
                        alpha: 0.6,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(20),
                        ),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: Motion.fast,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _trailingButton(context, canSend, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailingButton(
    BuildContext context,
    bool canSend,
    AppLocalizations l10n,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (widget.isStreaming) {
      return IconButton.filledTonal(
        key: const ValueKey('stop'),
        onPressed: widget.onCancel,
        tooltip: l10n.aiChatComposerStopTooltip,
        icon: const Icon(Icons.stop),
      );
    }
    if (widget.isFlushing) {
      return const Padding(
        key: ValueKey('flushing'),
        padding: EdgeInsets.all(8),
        child: SizedBox(width: 20, height: 20, child: FCircularProgress()),
      );
    }
    return IconButton.filled(
      key: const ValueKey('send'),
      onPressed: canSend ? _send : null,
      tooltip: l10n.aiChatComposerSendTooltip,
      style: IconButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        disabledBackgroundColor: cs.surfaceContainerHighest,
        disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.5),
        shape: const StadiumBorder(),
      ),
      icon: const Icon(Icons.arrow_upward),
    );
  }
}
