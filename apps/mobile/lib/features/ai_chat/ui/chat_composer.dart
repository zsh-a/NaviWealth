import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/ai/session/interaction_state.dart';
import '../../../core/ai/visual/visual.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../core/speech/speech_error_copy.dart';
import '../../../core/speech/speech_output.dart';
import '../../../core/speech/speech_recognizer.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../state/chat_controller.dart';
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
    this.onSendWithOrigin,
    this.isVoiceActive = false,
    this.canStartVoice = true,
    this.voiceCapabilities = SpeechRecognizerCapabilities.unknown,
    this.onStartVoice,
    this.onStopVoice,
    this.onCancelVoice,
    this.voiceCapsuleVisible = false,
    this.voicePhase = VoiceLifecyclePhase.idle,
    this.voiceTranscript = '',
    this.voiceErrorCode,
    this.voiceOutputErrorCode,
    this.voiceInputLane = InteractionInputLane.idle,
    this.voiceOutputLane = InteractionOutputLane.idle,
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

  /// Optional modality-aware submission path. Existing callers can continue
  /// using [onSend] for touch/keyboard input; voice-backed drafts use this
  /// callback so the ChatTurn carries its original input origin.
  final void Function(String text, InteractionInputOrigin origin)?
  onSendWithOrigin;

  /// Enables the session-level voice lane when both callbacks are supplied.
  /// Callers that omit them retain the draft-only dictation behavior.
  final bool isVoiceActive;
  final bool canStartVoice;
  final SpeechRecognizerCapabilities voiceCapabilities;
  final Future<void> Function()? onStartVoice;
  final Future<void> Function()? onStopVoice;
  final Future<void> Function()? onCancelVoice;
  final bool voiceCapsuleVisible;
  final VoiceLifecyclePhase voicePhase;
  final String voiceTranscript;
  final SpeechRecognitionErrorCode? voiceErrorCode;
  final SpeechOutputErrorCode? voiceOutputErrorCode;
  final InteractionInputLane voiceInputLane;
  final InteractionOutputLane voiceOutputLane;

  bool get voicePreparing => switch (voicePhase) {
    VoiceLifecyclePhase.preparing ||
    VoiceLifecyclePhase.permission ||
    VoiceLifecyclePhase.ready => true,
    _ => false,
  };
  bool get voiceFullDuplex =>
      voiceCapabilities.fullDuplex && voiceCapabilities.supportsBargeIn;

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
  InteractionInputOrigin? _draftInputOrigin;
  bool _voiceBusy = false;

  bool get _usesInteractionVoice =>
      !kIsWeb && widget.onStartVoice != null && widget.onStopVoice != null;

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
    final inputOrigin = _draftInputOrigin;
    setState(() {
      _replaceMessageId = null;
      _draftInputOrigin = null;
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
    final sendWithOrigin = widget.onSendWithOrigin;
    if (inputOrigin != null && sendWithOrigin != null) {
      sendWithOrigin(text, inputOrigin);
      return;
    }
    widget.onSend(text);
  }

  void _markSpeechInput() {
    _draftInputOrigin = InteractionInputOrigin.voice;
  }

  Future<void> _toggleVoice() async {
    if (_voiceBusy) return;
    final action = widget.isVoiceActive
        ? widget.onStopVoice
        : (widget.canStartVoice ? widget.onStartVoice : null);
    if (action == null) return;

    setState(() => _voiceBusy = true);
    try {
      await action();
    } on SpeechRecognitionException catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final message = speechRecognitionErrorMessage(l10n, error.code);
      AppMessenger.show(context, ToastKind.error, message);
      if (error.code == SpeechRecognitionErrorCode.modelNotInstalled) {
        unawaited(context.push(SettingsRoutes.aiModels));
      }
    } on Object {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).speechInputFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _cancelVoice() async {
    if (_voiceBusy &&
        !widget.voicePreparing &&
        !_isVoiceOutputLaneActive(widget.voiceOutputLane)) {
      return;
    }
    final action = widget.onCancelVoice;
    if (action == null) return;

    setState(() => _voiceBusy = true);
    try {
      await action();
    } on Object {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).speechInputFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
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
              if (_usesInteractionVoice && widget.voiceCapsuleVisible)
                _VoiceCapsule(
                  transcript: widget.voiceTranscript,
                  isListening: widget.isVoiceActive,
                  fullDuplex: widget.voiceFullDuplex,
                  isPreparing: widget.voicePreparing,
                  isEndpointing:
                      widget.voiceInputLane == InteractionInputLane.endpointing,
                  isSpeaking:
                      widget.voiceOutputLane ==
                          InteractionOutputLane.synthesizing ||
                      widget.voiceOutputLane == InteractionOutputLane.playing ||
                      widget.voiceOutputLane == InteractionOutputLane.paused,
                  busy: _voiceBusy,
                  onCancel: widget.onCancelVoice == null
                      ? null
                      : () => unawaited(_cancelVoice()),
                  phase: widget.voicePhase,
                ),
              if (_usesInteractionVoice &&
                  (widget.voiceErrorCode != null ||
                      widget.voiceOutputErrorCode != null))
                _VoiceErrorBanner(
                  message: widget.voiceErrorCode != null
                      ? speechRecognitionErrorMessage(
                          l10n,
                          widget.voiceErrorCode!,
                        )
                      : speechOutputErrorMessage(
                          l10n,
                          widget.voiceOutputErrorCode!,
                        ),
                ),
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
                      if (_usesInteractionVoice)
                        _InteractionVoiceButton(
                          active: widget.isVoiceActive,
                          fullDuplex: widget.voiceFullDuplex,
                          busy: _voiceBusy || widget.voicePreparing,
                          enabled: widget.isVoiceActive || widget.canStartVoice,
                          onPress: () => unawaited(_toggleVoice()),
                        )
                      else
                        SpeechInputButton(
                          controller: _controller,
                          enabled: !widget._busy,
                          onSpeechInput: _markSpeechInput,
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

class _VoiceErrorBanner extends StatelessWidget {
  const _VoiceErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2),
            child: Icon(
              FLucideIcons.circleAlert,
              size: AppIconSizes.xs,
              color: colors.destructive,
            ),
          ),
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(
              message,
              style: context.captionLabelStyle.copyWith(
                color: colors.destructive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceCapsule extends StatelessWidget {
  const _VoiceCapsule({
    required this.transcript,
    required this.isListening,
    required this.fullDuplex,
    required this.isPreparing,
    required this.isEndpointing,
    required this.isSpeaking,
    required this.busy,
    required this.onCancel,
    required this.phase,
  });

  final String transcript;
  final bool isListening;
  final bool fullDuplex;
  final bool isPreparing;
  final bool isEndpointing;
  final bool isSpeaking;
  final bool busy;
  final VoidCallback? onCancel;
  final VoiceLifecyclePhase phase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final status = isPreparing
        ? (phase == VoiceLifecyclePhase.permission
              ? l10n.speechInputPermissionStatus
              : l10n.speechInputPreparingStatus)
        : isSpeaking
        ? (fullDuplex
              ? l10n.speechInputDuplexSpeakingStatus
              : l10n.speechInputSpeakingStatus)
        : isListening
        ? (isEndpointing
              ? l10n.speechInputEndpointingStatus
              : fullDuplex
              ? l10n.speechInputContinuousStatus
              : l10n.speechInputListeningStatus)
        : l10n.speechInputThinkingStatus;
    final icon = isSpeaking
        ? FLucideIcons.sparkles
        : isEndpointing
        ? FLucideIcons.loaderCircle
        : FLucideIcons.mic;
    final text = transcript.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: AnimatedSize(
        duration: AppMotionPolicy.duration(context, Motion.fast),
        curve: Motion.standardDecelerate,
        alignment: Alignment.bottomCenter,
        child: SoftCard.flat(
          borderRadius: AppRadius.lg,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s10,
              AppSpacing.s8,
              AppSpacing.s10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _VoiceSignal(
                  active: isListening,
                  color: isSpeaking ? colors.primary : colors.foreground,
                ),
                const SizedBox(width: AppSpacing.s10),
                Icon(icon, size: AppIconSizes.sm, color: colors.primary),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (text.isNotEmpty)
                        Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.bodyCaptionStyle.copyWith(
                            color: colors.foreground,
                          ),
                        ),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.captionLabelStyle.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onCancel != null &&
                    (isListening || isPreparing || isSpeaking))
                  FTooltip(
                    tipBuilder: (_, _) => Text(
                      isSpeaking
                          ? (fullDuplex
                                ? l10n.speechInputContinuousStopTooltip
                                : l10n.speechOutputStopTooltip)
                          : fullDuplex
                          ? l10n.speechInputContinuousStopTooltip
                          : l10n.speechInputCancelTooltip,
                    ),
                    child: FButton.icon(
                      variant: FButtonVariant.ghost,
                      onPress: busy ? null : onCancel,
                      child: busy
                          ? const SizedBox.square(
                              dimension: AppIconSizes.sm,
                              child: FCircularProgress(),
                            )
                          : const Icon(FLucideIcons.x),
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

class _VoiceSignal extends StatelessWidget {
  const _VoiceSignal({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = <double>[8, 14, 10];
    return SizedBox(
      width: 14,
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final height in heights)
            AnimatedContainer(
              duration: AppMotionPolicy.duration(context, Motion.fast),
              width: 3,
              height: active ? height : 6,
              decoration: BoxDecoration(
                color: active
                    ? color
                    : color.withValues(alpha: AppOpacity.muted),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
        ],
      ),
    );
  }
}

class _InteractionVoiceButton extends StatelessWidget {
  const _InteractionVoiceButton({
    required this.active,
    required this.fullDuplex,
    required this.busy,
    required this.enabled,
    required this.onPress,
  });

  final bool active;
  final bool fullDuplex;
  final bool busy;
  final bool enabled;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tooltip = active
        ? (fullDuplex
              ? l10n.speechInputContinuousStopTooltip
              : l10n.speechInputStopTooltip)
        : busy
        ? l10n.speechInputStartingTooltip
        : (fullDuplex
              ? l10n.speechInputContinuousStartTooltip
              : l10n.speechInputStartTooltip);
    return FTooltip(
      tipBuilder: (_, _) => Text(tooltip),
      child: FButton.icon(
        variant: active ? FButtonVariant.destructive : FButtonVariant.secondary,
        onPress: enabled && !busy ? onPress : null,
        child: busy
            ? const SizedBox.square(
                dimension: AppIconSizes.sm,
                child: FCircularProgress(),
              )
            : Icon(active ? FLucideIcons.square : FLucideIcons.mic),
      ),
    );
  }
}

bool _isVoiceOutputLaneActive(InteractionOutputLane lane) =>
    lane == InteractionOutputLane.synthesizing ||
    lane == InteractionOutputLane.playing ||
    lane == InteractionOutputLane.paused;

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
            AppTappable(
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
          child: AppTappable(
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
        return AppMorphingAction(child: current(canSend));
      },
    );
  }
}
