import 'dart:async';

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
  late final ComposerDraftStore _draftStore;
  Timer? _persistTimer;

  /// When set, next submit replaces this user turn instead of appending.
  String? _replaceMessageId;

  @override
  void initState() {
    super.initState();
    _draftStore = ref.read(composerDraftStoreProvider);
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
    } else {
      _restorePersistedDraft();
    }
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    // Flush latest text once on dispose so a quick leave still saves.
    final sessionId = widget.sessionId;
    final text = _controller.text;
    final persistSessionId = _replaceMessageId == null ? sessionId : null;
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
    if (persistSessionId != null) {
      unawaited(_draftStore.save(persistSessionId, text));
    }
  }

  void _restorePersistedDraft() {
    final sessionId = widget.sessionId;
    if (sessionId == null) return;
    final saved = _draftStore.load(sessionId);
    if (saved == null || saved.isEmpty) return;
    _controller
      ..text = saved
      ..selection = TextSelection.collapsed(offset: saved.length);
  }

  void _onTextChanged() {
    final sessionId = widget.sessionId;
    if (sessionId == null || _replaceMessageId != null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        ref.read(composerDraftStoreProvider).save(sessionId, _controller.text),
      );
    });
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
    final sessionId = widget.sessionId;
    setState(() {
      _replaceMessageId = null;
      _controller.clear();
    });
    if (sessionId != null) {
      unawaited(ref.read(composerDraftStoreProvider).clear(sessionId));
    }
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

    final editing = _replaceMessageId != null;
    final colors = context.theme.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          top: BorderSide(
            color: colors.border.withValues(alpha: AppOpacity.scrim),
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
              AnimatedSize(
                duration: AppMotionPolicy.duration(context, Motion.fast),
                curve: Motion.standardDecelerate,
                alignment: Alignment.topCenter,
                child: editing
                    ? _EditBanner(
                        onCancel: () {
                          setState(() {
                            _replaceMessageId = null;
                            _controller.clear();
                          });
                          final sessionId = widget.sessionId;
                          if (sessionId != null) {
                            unawaited(
                              ref
                                  .read(composerDraftStoreProvider)
                                  .clear(sessionId),
                            );
                          }
                        },
                      )
                    : const SizedBox(width: double.infinity),
              ),
              if (sessionId != null) const _ProfileCaption(),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.muted.withValues(alpha: AppOpacity.prominent),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: editing
                        ? colors.primary.withValues(alpha: AppOpacity.scrim)
                        : colors.border.withValues(alpha: AppOpacity.scrim),
                    width: AppStroke.hairline,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    AppSpacing.s4,
                    AppSpacing.s4,
                    AppSpacing.s4,
                  ),
                  child: Row(
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
                                : (editing
                                      ? l10n.aiChatEditUserMessageTitle
                                      : l10n.aiChatComposerHintIdle),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s4),
                      SpeechInputButton(
                        controller: _controller,
                        enabled: !widget._busy,
                      ),
                      const SizedBox(width: AppSpacing.s4),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _EditBanner extends StatelessWidget {
  const _EditBanner({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: AppOpacity.subtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: colors.primary.withValues(alpha: AppOpacity.scrim),
            width: AppStroke.hairline,
          ),
        ),
        child: Row(
          children: [
            Icon(
              FLucideIcons.pencil,
              size: AppIconSizes.sm,
              color: colors.primary,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                l10n.aiChatEditBannerTitle,
                style: context.captionLabelStyle.copyWith(
                  color: colors.foreground,
                ),
              ),
            ),
            FTappable(
              onPress: onCancel,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s6,
                  vertical: AppSpacing.s2,
                ),
                child: Text(
                  l10n.aiChatEditCancel,
                  style: context.captionLabelStyle.copyWith(
                    color: colors.primary,
                  ),
                ),
              ),
            ),
          ],
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
                  style: AiType.meta(
                    context,
                  ).copyWith(color: AiTone.muted(context)),
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
